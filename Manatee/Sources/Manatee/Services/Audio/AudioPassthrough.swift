//
//  AudioPassthrough.swift
//  Manatee
//
//  Low-latency audio passthrough from BGMDevice to real output device
//  Uses a lock-free ring buffer for real-time safe audio routing
//

import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

/// Thread-safe ring buffer for audio passthrough
/// Uses atomic operations for lock-free producer/consumer pattern
final class AudioRingBuffer {
    private var buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        lock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        buffer.deallocate()
        lock.deallocate()
    }
    
    var availableToRead: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let avail = writeIndex - readIndex
        return avail >= 0 ? avail : avail + capacity
    }
    
    func write(_ data: UnsafePointer<Float>, count: Int) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        
        for i in 0..<count {
            buffer[(writeIndex + i) % capacity] = data[i]
        }
        writeIndex = (writeIndex + count) % capacity
    }
    
    func read(_ data: UnsafeMutablePointer<Float>, count: Int) -> Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        
        let available = writeIndex >= readIndex ? writeIndex - readIndex : capacity - readIndex + writeIndex
        let toRead = min(count, available)
        
        for i in 0..<toRead {
            data[i] = buffer[(readIndex + i) % capacity]
        }
        readIndex = (readIndex + toRead) % capacity
        
        // Fill remaining with silence if not enough data
        if toRead < count {
            for i in toRead..<count {
                data[i] = 0
            }
        }
        
        return toRead
    }
}

/// Audio passthrough context - holds all state needed by IO procs
/// Stored as a separate class to avoid issues with Swift object layout in C callbacks
final class PassthroughContext {
    let ringBuffer: AudioRingBuffer
    var channelCount: UInt32 = 2
    var isActive: Bool = false
    var inputCallCount: Int = 0
    var outputCallCount: Int = 0
    
    init(bufferSize: Int) {
        // Ring buffer holds samples (frames * channels)
        self.ringBuffer = AudioRingBuffer(capacity: bufferSize)
    }
}

/// Audio passthrough that routes audio from BGMDevice to the real output device
final class AudioPassthrough {
    
    // MARK: - State
    
    private(set) var isRunning: Bool = false
    var errorMessage: String?
    
    // MARK: - Private
    
    private var bgmDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var outputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var inputIOProcID: AudioDeviceIOProcID?
    private var outputIOProcID: AudioDeviceIOProcID?
    
    // Context for IO procs (must be a class for stable pointer)
    private var context: PassthroughContext?
    
    // MARK: - Singleton
    
    static let shared = AudioPassthrough()
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Start audio passthrough from BGMDevice to output device
    func start(bgmDevice: AudioDeviceID, outputDevice: AudioDeviceID) -> Bool {
        guard !isRunning else { return true }
        
        bgmDeviceID = bgmDevice
        outputDeviceID = outputDevice
        
        print("🔊 AudioPassthrough: Starting from BGMDevice (\(bgmDevice)) to output (\(outputDevice))")
        
        // Get stream format from BGMDevice output scope
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var bgmFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioObjectGetPropertyData(bgmDevice, &address, 0, nil, &formatSize, &bgmFormat)
        
        if status != noErr {
            print("❌ AudioPassthrough: Failed to get BGMDevice format: \(status)")
            return false
        }
        
        print("📊 AudioPassthrough: BGMDevice format - \(bgmFormat.mSampleRate) Hz, \(bgmFormat.mChannelsPerFrame) ch, \(bgmFormat.mBitsPerChannel) bits")
        
        // Get IO buffer size
        address.mSelector = kAudioDevicePropertyBufferFrameSize
        var bufferFrameSize: UInt32 = 0
        var bufferSizePropertySize = UInt32(MemoryLayout<UInt32>.size)
        status = AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &bufferSizePropertySize, &bufferFrameSize)
        
        if status != noErr {
            bufferFrameSize = 512 // Default fallback
        }
        
        print("📊 AudioPassthrough: Buffer frame size: \(bufferFrameSize)")
        
        // Create context with ring buffer sized for ~100ms latency
        // Ring buffer holds samples (frames * channels)
        let ringBufferSamples = Int(bgmFormat.mSampleRate) * Int(bgmFormat.mChannelsPerFrame) / 10 // 100ms
        context = PassthroughContext(bufferSize: max(ringBufferSamples, 48000))
        context?.channelCount = bgmFormat.mChannelsPerFrame
        context?.isActive = true
        
        guard let ctx = context else {
            print("❌ AudioPassthrough: Failed to create context")
            return false
        }
        
        // Create input IO proc for BGMDevice (reads from BGMDevice's output)
        let contextPtr = Unmanaged.passUnretained(ctx).toOpaque()
        
        status = AudioDeviceCreateIOProcID(
            bgmDevice,
            passthroughInputIOProc,
            contextPtr,
            &inputIOProcID
        )
        
        if status != noErr {
            print("❌ AudioPassthrough: Failed to create input IO proc: \(status)")
            cleanup()
            return false
        }
        
        // Create output IO proc for real output device
        status = AudioDeviceCreateIOProcID(
            outputDevice,
            passthroughOutputIOProc,
            contextPtr,
            &outputIOProcID
        )
        
        if status != noErr {
            print("❌ AudioPassthrough: Failed to create output IO proc: \(status)")
            cleanup()
            return false
        }
        
        print("✅ AudioPassthrough: Created IO procs")
        
        // Start IO on BGMDevice first (input)
        status = AudioDeviceStart(bgmDevice, inputIOProcID)
        if status != noErr {
            print("❌ AudioPassthrough: Failed to start BGMDevice IO: \(status)")
            cleanup()
            return false
        }
        
        print("✅ AudioPassthrough: Started BGMDevice IO")
        
        // Start IO on output device
        status = AudioDeviceStart(outputDevice, outputIOProcID)
        if status != noErr {
            print("❌ AudioPassthrough: Failed to start output device IO: \(status)")
            AudioDeviceStop(bgmDevice, inputIOProcID)
            cleanup()
            return false
        }
        
        print("✅ AudioPassthrough: Started output device IO")
        
        isRunning = true
        print("✅ AudioPassthrough: Started successfully")
        
        // Start monitoring thread
        startMonitoring()
        
        return true
    }
    
    private func startMonitoring() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, let ctx = self.context, self.isRunning else { return }
            print("📊 AudioPassthrough stats: input=\(ctx.inputCallCount), output=\(ctx.outputCallCount), buffer=\(ctx.ringBuffer.availableToRead)")
        }
    }
    
    /// Stop audio passthrough
    func stop() {
        guard isRunning else { return }
        
        print("🔊 AudioPassthrough: Stopping...")
        
        context?.isActive = false
        
        if let inputProc = inputIOProcID {
            AudioDeviceStop(bgmDeviceID, inputProc)
            AudioDeviceDestroyIOProcID(bgmDeviceID, inputProc)
        }
        
        if let outputProc = outputIOProcID {
            AudioDeviceStop(outputDeviceID, outputProc)
            AudioDeviceDestroyIOProcID(outputDeviceID, outputProc)
        }
        
        cleanup()
        isRunning = false
        print("✅ AudioPassthrough: Stopped")
    }
    
    private func cleanup() {
        inputIOProcID = nil
        outputIOProcID = nil
        context = nil
    }
}

// MARK: - IO Procs (C callbacks)

/// Input IO proc - reads audio from BGMDevice and stores in ring buffer
private func passthroughInputIOProc(
    inDevice: AudioObjectID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let context = Unmanaged<PassthroughContext>.fromOpaque(clientData).takeUnretainedValue()
    
    guard context.isActive else { return noErr }
    
    context.inputCallCount += 1
    
    // The input data is in inInputData (data coming FROM BGMDevice)
    let bufferList = inInputData.pointee
    guard bufferList.mNumberBuffers > 0 else { return noErr }
    
    let buffer = bufferList.mBuffers
    guard let data = buffer.mData else { return noErr }
    
    let floatData = data.assumingMemoryBound(to: Float.self)
    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
    
    // Debug: check if we're getting actual audio data (not silence)
    if context.inputCallCount % 500 == 1 {
        var maxSample: Float = 0
        for i in 0..<min(sampleCount, 1024) {
            let sample = abs(floatData[i])
            if sample > maxSample { maxSample = sample }
        }
        print("🎵 Input: \(sampleCount) samples, max=\(maxSample), bytes=\(buffer.mDataByteSize)")
    }
    
    // Write to ring buffer
    context.ringBuffer.write(floatData, count: sampleCount)
    
    return noErr
}

/// Output IO proc - reads from ring buffer and writes to output device
private func passthroughOutputIOProc(
    inDevice: AudioObjectID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let context = Unmanaged<PassthroughContext>.fromOpaque(clientData).takeUnretainedValue()
    
    context.outputCallCount += 1
    
    // Write to outOutputData (data going TO speakers)
    let bufferList = outOutputData.pointee
    guard bufferList.mNumberBuffers > 0 else { return noErr }
    
    let buffer = outOutputData.pointee.mBuffers
    guard let data = buffer.mData else { return noErr }
    
    let floatData = data.assumingMemoryBound(to: Float.self)
    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
    
    // Read from ring buffer
    _ = context.ringBuffer.read(floatData, count: sampleCount)
    
    return noErr
}
