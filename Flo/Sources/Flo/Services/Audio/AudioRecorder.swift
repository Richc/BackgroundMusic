//
//  AudioRecorder.swift
//  Flo
//
//  Multi-channel WAV file recorder
//  Supports recording up to 4 channels simultaneously
//

import Foundation
import AVFoundation
import AudioToolbox
import AppKit

/// Individual recording session for a single channel
final class RecordingSession {
    let id: UUID
    let channelId: UUID
    let channelName: String
    let filePath: URL
    
    private var audioFile: ExtAudioFileRef?
    private let format: AudioStreamBasicDescription
    private var framesWritten: Int64 = 0
    private let lock = NSLock()
    
    var isRecording: Bool { audioFile != nil }
    var duration: TimeInterval { Double(framesWritten) / format.mSampleRate }
    
    init(channelId: UUID, channelName: String, sampleRate: Double = 44100, channels: UInt32 = 2, savePath: URL? = nil, fullFilePath: URL? = nil) throws {
        self.id = UUID()
        self.channelId = channelId
        self.channelName = channelName
        
        // Create WAV format (16-bit PCM)
        var wavFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,  // 2 channels * 2 bytes per sample
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        // Float input format (what we receive from audio callbacks)
        self.format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * Int(channels)),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * Int(channels)),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        // Determine file path
        if let fullPath = fullFilePath {
            // Use the full file path directly
            let folder = fullPath.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.filePath = fullPath
        } else {
            // Generate filename
            let safeName = channelName.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let filename = "\(safeName).wav"
            
            // Use custom path or default to Music folder
            let floFolder: URL
            if let customPath = savePath {
                floFolder = customPath
            } else {
                let musicFolder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
                floFolder = musicFolder.appendingPathComponent("Flo Recordings", isDirectory: true)
            }
            
            // Create folder if needed
            try? FileManager.default.createDirectory(at: floFolder, withIntermediateDirectories: true)
            
            self.filePath = floFolder.appendingPathComponent(filename)
        }
        
        // Create audio file
        var fileRef: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(
            filePath as CFURL,
            kAudioFileWAVEType,
            &wavFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &fileRef
        )
        
        guard status == noErr, let file = fileRef else {
            throw NSError(domain: "AudioRecorder", code: Int(status), 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create audio file"])
        }
        
        // Set client format (what we write as)
        var clientFormat = format
        status = ExtAudioFileSetProperty(
            file,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        
        guard status == noErr else {
            ExtAudioFileDispose(file)
            throw NSError(domain: "AudioRecorder", code: Int(status),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set client format"])
        }
        
        self.audioFile = file
        print("🎙️ Recording started: \(filePath.lastPathComponent)")
    }
    
    /// Write audio buffer to file (called from audio thread)
    func writeBuffer(_ buffer: UnsafePointer<Float>, frameCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let file = audioFile else { return }
        
        let bytesPerFrame = Int(format.mBytesPerFrame)
        let dataSize = frameCount * bytesPerFrame
        
        var audioBuffer = AudioBuffer(
            mNumberChannels: format.mChannelsPerFrame,
            mDataByteSize: UInt32(dataSize),
            mData: UnsafeMutableRawPointer(mutating: buffer)
        )
        
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
        
        let status = ExtAudioFileWrite(file, UInt32(frameCount), &bufferList)
        if status == noErr {
            framesWritten += Int64(frameCount)
            // Debug: log every ~1 second (44100 frames per second for 44.1kHz)
            if framesWritten % 44100 < Int64(frameCount) {
                print("🎙️ Recording progress: \(String(format: "%.1f", Double(framesWritten) / 44100.0))s written")
            }
        } else {
            print("❌ ExtAudioFileWrite failed with status: \(status)")
        }
    }
    
    /// Stop recording and close file
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        if let file = audioFile {
            ExtAudioFileDispose(file)
            audioFile = nil
            print("🎙️ Recording stopped: \(filePath.lastPathComponent) (\(String(format: "%.1f", duration))s)")
        }
    }
    
    deinit {
        stop()
    }
}

/// Multi-channel audio recorder manager
@MainActor
final class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()
    
    /// Maximum concurrent recordings
    static let maxRecordings = 4
    
    /// Active recording sessions
    @Published private(set) var sessions: [RecordingSession] = []
    
    /// Whether any recording is active
    var isRecording: Bool { !sessions.isEmpty }
    
    /// Number of active recordings
    var activeCount: Int { sessions.count }
    
    /// Check if a specific channel is recording
    func isChannelRecording(_ channelId: UUID) -> Bool {
        sessions.contains { $0.channelId == channelId }
    }
    
    /// Start recording for a channel
    func startRecording(channelId: UUID, channelName: String, sampleRate: Double = 44100, savePath: URL? = nil) throws {
        // Check max recordings
        guard sessions.count < Self.maxRecordings else {
            throw NSError(domain: "AudioRecorder", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Maximum \(Self.maxRecordings) recordings allowed"])
        }
        
        // Check if already recording this channel
        guard !isChannelRecording(channelId) else {
            throw NSError(domain: "AudioRecorder", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Already recording this channel"])
        }
        
        let session = try RecordingSession(channelId: channelId, channelName: channelName, sampleRate: sampleRate, savePath: savePath)
        sessions.append(session)
    }
    
    /// Stop recording for a specific channel
    func stopRecording(channelId: UUID) {
        if let index = sessions.firstIndex(where: { $0.channelId == channelId }) {
            let session = sessions.remove(at: index)
            session.stop()
        }
    }
    
    /// Stop all recordings
    func stopAllRecordings() {
        for session in sessions {
            session.stop()
        }
        sessions.removeAll()
    }
    
    /// Get session for a channel
    func session(for channelId: UUID) -> RecordingSession? {
        sessions.first { $0.channelId == channelId }
    }
    
    /// Write audio data for a channel (non-isolated for audio thread access)
    nonisolated func writeAudio(channelId: UUID, buffer: UnsafePointer<Float>, frameCount: Int) {
        // Find session on current thread (sessions array is accessed unsafely here for performance)
        // This is acceptable because recording sessions are relatively stable
        Task { @MainActor in
            if let session = self.sessions.first(where: { $0.channelId == channelId }) {
                session.writeBuffer(buffer, frameCount: frameCount)
            }
        }
    }
    
    /// Open the recordings folder in Finder
    func openRecordingsFolder() {
        let musicFolder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
        let floFolder = musicFolder.appendingPathComponent("Flo Recordings", isDirectory: true)
        NSWorkspace.shared.open(floFolder)
    }
    
    private init() {}
}

// MARK: - Recording Context for Audio Thread

/// Thread-safe recording context for use in audio callbacks
/// This is a non-actor class that can be safely accessed from the audio thread
final class RecordingContext {
    private var activeSessions: [UUID: RecordingSession] = [:]
    private let lock = NSLock()
    
    /// Master recording session (for capturing full mix)
    private var masterSession: RecordingSession?
    private(set) var isMasterRecording: Bool = false
    
    static let shared = RecordingContext()
    
    private init() {}
    
    /// Register a session for a channel
    func registerSession(_ session: RecordingSession, for channelId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions[channelId] = session
    }
    
    /// Unregister a session
    func unregisterSession(for channelId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions.removeValue(forKey: channelId)
    }
    
    /// Check if a channel is recording (thread-safe)
    func isRecording(_ channelId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeSessions[channelId] != nil
    }
    
    /// Write audio for a channel (called from audio thread)
    func writeAudio(channelId: UUID, buffer: UnsafePointer<Float>, frameCount: Int) {
        lock.lock()
        let session = activeSessions[channelId]
        lock.unlock()
        
        session?.writeBuffer(buffer, frameCount: frameCount)
    }
    
    /// Start master recording (captures full mix)
    func startMasterRecording(sampleRate: Double = 44100, savePath: URL? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard masterSession == nil else { return }
        
        masterSession = try RecordingSession(
            channelId: UUID(),
            channelName: "Master Mix",
            sampleRate: sampleRate,
            fullFilePath: savePath
        )
        isMasterRecording = true
        print("🎙️ Master recording started - isMasterRecording: \(isMasterRecording)")
    }
    
    /// Stop master recording
    func stopMasterRecording() {
        lock.lock()
        defer { lock.unlock() }
        
        masterSession?.stop()
        masterSession = nil
        isMasterRecording = false
    }
    
    /// Write master output (called from output audio callback)
    func writeMasterAudio(buffer: UnsafePointer<Float>, frameCount: Int) {
        lock.lock()
        let session = masterSession
        lock.unlock()
        
        session?.writeBuffer(buffer, frameCount: frameCount)
    }
}
