//
//  VADManager.swift
//  VAD-Test
//
//  Created for Silero VAD CoreML integration
//

import CoreML
import AVFoundation
import Accelerate

class VADManager: NSObject, ObservableObject {
    @Published var isVoiceDetected: Bool = false
    @Published var voiceProbability: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var error: String?
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFormat: AVAudioFormat?
    
    private let sampleRate: Double = 16000
    private let chunkSize: Int = 512  // 32ms at 16kHz
    @Published var threshold: Float = 0.5  // Adjustable threshold as Silero recommends
    
    private var audioBuffer: [Float] = []
    private let bufferQueue = DispatchQueue(label: "vad.buffer.queue")
    
    // Silero VAD instance
    private let sileroVAD = SileroVAD()
    
    // Smoothing for probability - as recommended for noisy environments
    private var probabilityHistory: [Float] = []
    @Published var minSpeechDuration: Int = 8  // Minimum chunks for speech (~256ms)
    @Published var minSilenceDuration: Int = 5  // Minimum chunks for silence (~160ms)
    
    // Speech state tracking
    private var speechChunkCount = 0
    private var silenceChunkCount = 0
    private var isSpeaking = false
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true)
            try audioSession.setPreferredSampleRate(sampleRate)
        } catch {
            self.error = "Failed to setup audio session: \(error.localizedDescription)"
        }
    }
    
    
    func startRecording() {
        guard !isRecording else { return }
        
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        guard let inputNode = inputNode else {
            self.error = "Failed to get audio input node"
            return
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create format for 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            self.error = "Failed to create audio format"
            return
        }
        
        let converter = AVAudioConverter(from: recordingFormat, to: targetFormat)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert to target format
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / recordingFormat.sampleRate)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter?.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                DispatchQueue.main.async {
                    self.error = "Audio conversion error: \(error.localizedDescription)"
                }
                return
            }
            
            self.processAudioBuffer(pcmBuffer)
        }
        
        do {
            try audioEngine?.start()
            DispatchQueue.main.async {
                self.isRecording = true
                self.error = nil
            }
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        sileroVAD.resetState() // Reset RNN state
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.audioBuffer.append(contentsOf: samples)
            
            // Process chunks of 512 samples (32ms at 16kHz)
            while self.audioBuffer.count >= self.chunkSize {
                let chunk = Array(self.audioBuffer.prefix(self.chunkSize))
                self.audioBuffer.removeFirst(self.chunkSize)
                
                let probability = self.processChunk(chunk)
                
                // Implement minimal speech/silence duration as Silero recommends
                if probability > self.threshold {
                    self.speechChunkCount += 1
                    self.silenceChunkCount = 0
                    
                    // Only trigger speech after minimum duration
                    if !self.isSpeaking && self.speechChunkCount >= self.minSpeechDuration {
                        self.isSpeaking = true
                    }
                } else {
                    self.silenceChunkCount += 1
                    self.speechChunkCount = 0
                    
                    // Only stop speech after minimum silence duration
                    if self.isSpeaking && self.silenceChunkCount >= self.minSilenceDuration {
                        self.isSpeaking = false
                    }
                }
                
                DispatchQueue.main.async {
                    self.voiceProbability = probability
                    self.isVoiceDetected = self.isSpeaking
                }
            }
        }
    }
    
    private func processChunk(_ chunk: [Float]) -> Float {
        // Use the SileroVAD implementation
        return sileroVAD.processAudioChunk(chunk)
    }
}