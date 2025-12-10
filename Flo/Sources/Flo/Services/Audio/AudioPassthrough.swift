//
//  AudioPassthrough.swift
//  Flo
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

/// 3-Band EQ using biquad filters
/// Low: Shelf filter at 250 Hz
/// Mid: Peak filter at 1 kHz  
/// High: Shelf filter at 4 kHz
final class ThreeBandEQ {
    // Filter coefficients for stereo (2 channels)
    private var lowShelfCoeffs: [Double] = [1, 0, 0, 0, 0]  // b0, b1, b2, a1, a2
    private var midPeakCoeffs: [Double] = [1, 0, 0, 0, 0]
    private var highShelfCoeffs: [Double] = [1, 0, 0, 0, 0]
    
    // Filter delay states (2 delays per biquad section, per channel)
    private var lowDelayL: [Double] = [0, 0]
    private var lowDelayR: [Double] = [0, 0]
    private var midDelayL: [Double] = [0, 0]
    private var midDelayR: [Double] = [0, 0]
    private var highDelayL: [Double] = [0, 0]
    private var highDelayR: [Double] = [0, 0]
    
    // EQ parameters (gain in dB, -12 to +12)
    var lowGain: Float = 0 { didSet { updateLowShelf() } }
    var midGain: Float = 0 { didSet { updateMidPeak() } }
    var highGain: Float = 0 { didSet { updateHighShelf() } }
    
    private var sampleRate: Double = 48000
    
    init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        updateAllFilters()
    }
    
    func setSampleRate(_ rate: Double) {
        sampleRate = rate
        updateAllFilters()
    }
    
    private func updateAllFilters() {
        updateLowShelf()
        updateMidPeak()
        updateHighShelf()
    }
    
    // Low shelf filter at 200 Hz
    private func updateLowShelf() {
        let freq = 200.0
        let gain = Double(lowGain)
        lowShelfCoeffs = calculateShelfCoefficients(freq: freq, gain: gain, isLowShelf: true)
    }
    
    // Mid peak filter at 1 kHz (Q = 0.5 for wide bandwidth)
    private func updateMidPeak() {
        let freq = 1000.0
        let gain = Double(midGain)
        let Q = 0.5
        midPeakCoeffs = calculatePeakCoefficients(freq: freq, gain: gain, Q: Q)
    }
    
    // High shelf filter at 3 kHz
    private func updateHighShelf() {
        let freq = 3000.0
        let gain = Double(highGain)
        highShelfCoeffs = calculateShelfCoefficients(freq: freq, gain: gain, isLowShelf: false)
    }
    
    // Calculate low/high shelf filter coefficients
    private func calculateShelfCoefficients(freq: Double, gain: Double, isLowShelf: Bool) -> [Double] {
        if abs(gain) < 0.1 { return [1, 0, 0, 0, 0] }  // Bypass if nearly flat
        
        let A = pow(10, gain / 40)  // Amplitude
        let w0 = 2 * Double.pi * freq / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let S = 1.0  // Shelf slope
        let alpha = sinw0 / 2 * sqrt((A + 1/A) * (1/S - 1) + 2)
        
        var b0, b1, b2, a0, a1, a2: Double
        
        if isLowShelf {
            b0 = A * ((A + 1) - (A - 1) * cosw0 + 2 * sqrt(A) * alpha)
            b1 = 2 * A * ((A - 1) - (A + 1) * cosw0)
            b2 = A * ((A + 1) - (A - 1) * cosw0 - 2 * sqrt(A) * alpha)
            a0 = (A + 1) + (A - 1) * cosw0 + 2 * sqrt(A) * alpha
            a1 = -2 * ((A - 1) + (A + 1) * cosw0)
            a2 = (A + 1) + (A - 1) * cosw0 - 2 * sqrt(A) * alpha
        } else {
            b0 = A * ((A + 1) + (A - 1) * cosw0 + 2 * sqrt(A) * alpha)
            b1 = -2 * A * ((A - 1) + (A + 1) * cosw0)
            b2 = A * ((A + 1) + (A - 1) * cosw0 - 2 * sqrt(A) * alpha)
            a0 = (A + 1) - (A - 1) * cosw0 + 2 * sqrt(A) * alpha
            a1 = 2 * ((A - 1) - (A + 1) * cosw0)
            a2 = (A + 1) - (A - 1) * cosw0 - 2 * sqrt(A) * alpha
        }
        
        // Normalize
        return [b0/a0, b1/a0, b2/a0, a1/a0, a2/a0]
    }
    
    // Calculate peak (parametric) filter coefficients
    private func calculatePeakCoefficients(freq: Double, gain: Double, Q: Double) -> [Double] {
        if abs(gain) < 0.1 { return [1, 0, 0, 0, 0] }  // Bypass if nearly flat
        
        let A = pow(10, gain / 40)
        let w0 = 2 * Double.pi * freq / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2 * Q)
        
        let b0 = 1 + alpha * A
        let b1 = -2 * cosw0
        let b2 = 1 - alpha * A
        let a0 = 1 + alpha / A
        let a1 = -2 * cosw0
        let a2 = 1 - alpha / A
        
        return [b0/a0, b1/a0, b2/a0, a1/a0, a2/a0]
    }
    
    // Process a single sample through a biquad filter
    @inline(__always)
    private func processBiquad(_ input: Double, coeffs: [Double], delay: inout [Double]) -> Double {
        let output = coeffs[0] * input + delay[0]
        delay[0] = coeffs[1] * input - coeffs[3] * output + delay[1]
        delay[1] = coeffs[2] * input - coeffs[4] * output
        return output
    }
    
    // Process interleaved stereo buffer in-place
    func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int, channelCount: Int) {
        guard channelCount >= 2 else { return }
        
        for frame in 0..<frameCount {
            let leftIdx = frame * channelCount
            let rightIdx = leftIdx + 1
            
            var left = Double(buffer[leftIdx])
            var right = Double(buffer[rightIdx])
            
            // Apply all three bands in series
            left = processBiquad(left, coeffs: lowShelfCoeffs, delay: &lowDelayL)
            right = processBiquad(right, coeffs: lowShelfCoeffs, delay: &lowDelayR)
            
            left = processBiquad(left, coeffs: midPeakCoeffs, delay: &midDelayL)
            right = processBiquad(right, coeffs: midPeakCoeffs, delay: &midDelayR)
            
            left = processBiquad(left, coeffs: highShelfCoeffs, delay: &highDelayL)
            right = processBiquad(right, coeffs: highShelfCoeffs, delay: &highDelayR)
            
            buffer[leftIdx] = Float(left)
            buffer[rightIdx] = Float(right)
        }
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
    
    /// System volume (from BGMDevice volume control or keyboard) - applied during output
    var systemVolume: Float = 1.0
    
    /// Peak levels for meters (updated atomically from audio thread)
    var peakLevelLeft: Float = 0
    var peakLevelRight: Float = 0
    
    /// 3-band EQ processor
    let eq: ThreeBandEQ
    
    init(bufferSize: Int, sampleRate: Double = 48000) {
        // Ring buffer holds samples (frames * channels)
        self.ringBuffer = AudioRingBuffer(capacity: bufferSize)
        self.eq = ThreeBandEQ(sampleRate: sampleRate)
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
        context = PassthroughContext(bufferSize: max(ringBufferSamples, 48000), sampleRate: bgmFormat.mSampleRate)
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
    
    /// Set the system volume (called when keyboard volume changes)
    func setSystemVolume(_ volume: Float) {
        context?.systemVolume = volume
        print("🔊 AudioPassthrough: System volume set to \(Int(volume * 100))%")
    }
    
    /// Get current system volume
    var systemVolume: Float {
        context?.systemVolume ?? 1.0
    }
    
    /// Get and reset peak levels for meters
    /// Returns (left, right) peak levels in 0.0-1.0 range
    func getPeakLevelsAndReset() -> (left: Float, right: Float) {
        guard let ctx = context else { return (0, 0) }
        
        let left = ctx.peakLevelLeft
        let right = ctx.peakLevelRight
        
        // Reset for next measurement
        ctx.peakLevelLeft = 0
        ctx.peakLevelRight = 0
        
        return (left, right)
    }
    
    // MARK: - 3-Band EQ Control
    
    /// Set low band gain (-12 to +12 dB)
    func setEQLowGain(_ gain: Float) {
        context?.eq.lowGain = max(-12, min(12, gain))
    }
    
    /// Set mid band gain (-12 to +12 dB)
    func setEQMidGain(_ gain: Float) {
        context?.eq.midGain = max(-12, min(12, gain))
    }
    
    /// Set high band gain (-12 to +12 dB)
    func setEQHighGain(_ gain: Float) {
        context?.eq.highGain = max(-12, min(12, gain))
    }
    
    /// Get current EQ gains
    var eqLowGain: Float { context?.eq.lowGain ?? 0 }
    var eqMidGain: Float { context?.eq.midGain ?? 0 }
    var eqHighGain: Float { context?.eq.highGain ?? 0 }
    
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
    
    let channelCount = Int(context.channelCount)
    let frameCount = sampleCount / max(1, channelCount)
    
    // Apply 3-band EQ
    context.eq.process(floatData, frameCount: frameCount, channelCount: channelCount)
    
    // Apply system volume (from keyboard volume keys)
    let volume = context.systemVolume
    if volume < 0.999 {  // Only process if not at unity
        for i in 0..<sampleCount {
            floatData[i] *= volume
        }
    }
    
    // Write to master recording if active (after all processing, this is what goes to speakers)
    if RecordingContext.shared.isMasterRecording {
        RecordingContext.shared.writeMasterAudio(buffer: floatData, frameCount: frameCount)
    }
    
    // Calculate peak levels for meters (interleaved stereo: L R L R L R...)
    var peakL: Float = 0
    var peakR: Float = 0
    
    for frame in 0..<frameCount {
        let baseIndex = frame * channelCount
        if channelCount >= 1 {
            let sampleL = abs(floatData[baseIndex])
            if sampleL > peakL { peakL = sampleL }
        }
        if channelCount >= 2 {
            let sampleR = abs(floatData[baseIndex + 1])
            if sampleR > peakR { peakR = sampleR }
        }
    }
    
    // Update context peak levels (simple max, will be decayed on read)
    if peakL > context.peakLevelLeft { context.peakLevelLeft = peakL }
    if peakR > context.peakLevelRight { context.peakLevelRight = peakR }
    
    return noErr
}
