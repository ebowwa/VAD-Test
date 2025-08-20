//
//  SileroVAD.swift
//  VAD-Test
//
//  Simplified Silero VAD implementation based on FluidAudio approach
//

import CoreML
import AVFoundation
import Accelerate

class SileroVAD {
    private var stftModel: MLModel?
    private var encoderModel: MLModel?
    private var decoderModel: MLModel?
    
    // RNN hidden states
    private var h_n: MLMultiArray?
    private var c_n: MLMultiArray?
    
    // Model parameters
    private let hiddenSize: Int = 64
    private let sampleRate: Int = 16000
    private let windowSize: Int = 512  // 32ms at 16kHz
    
    init() {
        loadModels()
        resetState()
    }
    
    private func loadModels() {
        do {
            if let stftURL = Bundle.main.url(forResource: "silero_stft", withExtension: "mlmodelc") {
                stftModel = try MLModel(contentsOf: stftURL)
                print("✅ Loaded STFT model")
            }
            
            if let encoderURL = Bundle.main.url(forResource: "silero_encoder", withExtension: "mlmodelc") {
                encoderModel = try MLModel(contentsOf: encoderURL)
                print("✅ Loaded Encoder model")
            }
            
            if let decoderURL = Bundle.main.url(forResource: "silero_rnn_decoder", withExtension: "mlmodelc") {
                decoderModel = try MLModel(contentsOf: decoderURL)
                print("✅ Loaded Decoder model")
            }
        } catch {
            print("❌ Error loading models: \(error)")
        }
    }
    
    func resetState() {
        do {
            // Initialize RNN states with zeros
            h_n = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize)], dataType: .float32)
            c_n = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize)], dataType: .float32)
            
            for i in 0..<hiddenSize {
                h_n![i] = 0
                c_n![i] = 0
            }
        } catch {
            print("❌ Failed to reset state: \(error)")
        }
    }
    
    func processAudioChunk(_ audioChunk: [Float]) -> Float {
        guard audioChunk.count == windowSize else {
            print("⚠️ Invalid chunk size: \(audioChunk.count), expected \(windowSize)")
            return 0.0
        }
        
        guard let stftModel = stftModel,
              let encoderModel = encoderModel,
              let decoderModel = decoderModel,
              let h_n = h_n,
              let c_n = c_n else {
            print("⚠️ Models not loaded, using fallback")
            return fallbackVAD(audioChunk)
        }
        
        do {
            // Step 1: STFT Transform
            let audioInput = try MLMultiArray(shape: [1, NSNumber(value: windowSize)], dataType: .float32)
            for i in 0..<windowSize {
                audioInput[i] = NSNumber(value: audioChunk[i])
            }
            
            // Try common input/output names for STFT
            var stftOutput: MLFeatureProvider?
            let stftInputNames = ["input", "audio", "audio_chunk", "x", "input_1"]
            
            for inputName in stftInputNames {
                do {
                    let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: audioInput])
                    stftOutput = try stftModel.prediction(from: provider)
                    print("✅ STFT input name: \(inputName)")
                    break
                } catch {
                    continue
                }
            }
            
            guard let stftResult = stftOutput else {
                print("❌ Could not run STFT")
                return fallbackVAD(audioChunk)
            }
            
            // Get STFT features
            let stftOutputNames = ["output", "stft", "features", "y", "var_313", "output_1"]
            var stftFeatures: MLMultiArray?
            
            for outputName in stftOutputNames {
                if let features = stftResult.featureValue(for: outputName)?.multiArrayValue {
                    stftFeatures = features
                    print("✅ STFT output name: \(outputName), shape: \(features.shape)")
                    break
                }
            }
            
            guard let stft = stftFeatures else {
                print("❌ Could not get STFT output")
                // Print available feature names for debugging
                for name in stftResult.featureNames {
                    print("Available STFT output: \(name)")
                }
                return fallbackVAD(audioChunk)
            }
            
            // Step 2: Encoder
            let encoderInputNames = ["input", "stft", "features", "x", "input_1"]
            var encoderOutput: MLFeatureProvider?
            
            for inputName in encoderInputNames {
                do {
                    let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: stft])
                    encoderOutput = try encoderModel.prediction(from: provider)
                    print("✅ Encoder input name: \(inputName)")
                    break
                } catch {
                    continue
                }
            }
            
            guard let encoderResult = encoderOutput else {
                print("❌ Could not run Encoder")
                return fallbackVAD(audioChunk)
            }
            
            // Get encoder features
            let encoderOutputNames = ["output", "encoded", "features", "y", "var_567", "output_1"]
            var encoderFeatures: MLMultiArray?
            
            for outputName in encoderOutputNames {
                if let features = encoderResult.featureValue(for: outputName)?.multiArrayValue {
                    encoderFeatures = features
                    print("✅ Encoder output name: \(outputName), shape: \(features.shape)")
                    break
                }
            }
            
            guard let encoded = encoderFeatures else {
                print("❌ Could not get Encoder output")
                // Print available feature names for debugging
                for name in encoderResult.featureNames {
                    print("Available Encoder output: \(name)")
                }
                return fallbackVAD(audioChunk)
            }
            
            // Step 3: RNN Decoder
            // Try different input combinations
            let decoderInputConfigs = [
                ["input": encoded, "h": h_n, "c": c_n],
                ["x": encoded, "h_0": h_n, "c_0": c_n],
                ["input": encoded, "h_0": h_n, "c_0": c_n],
                ["features": encoded, "h": h_n, "c": c_n],
                ["input_1": encoded, "input_2": h_n, "input_3": c_n]
            ]
            
            var decoderOutput: MLFeatureProvider?
            
            for config in decoderInputConfigs {
                do {
                    let provider = try MLDictionaryFeatureProvider(dictionary: config)
                    decoderOutput = try decoderModel.prediction(from: provider)
                    print("✅ Decoder config worked")
                    break
                } catch {
                    continue
                }
            }
            
            guard let decoderResult = decoderOutput else {
                print("❌ Could not run Decoder")
                return fallbackVAD(audioChunk)
            }
            
            // Update RNN states
            let stateNames = [
                ("h_n", "c_n"),
                ("h_out", "c_out"),
                ("h", "c"),
                ("output_h", "output_c")
            ]
            
            for (hName, cName) in stateNames {
                if let newH = decoderResult.featureValue(for: hName)?.multiArrayValue,
                   let newC = decoderResult.featureValue(for: cName)?.multiArrayValue {
                    self.h_n = newH
                    self.c_n = newC
                    print("✅ Updated states: \(hName), \(cName)")
                    break
                }
            }
            
            // Get probability output
            let probNames = ["output", "probability", "vad", "y", "var_850", "output_1", "prob"]
            
            for name in probNames {
                if let probArray = decoderResult.featureValue(for: name)?.multiArrayValue {
                    let probability = Float(truncating: probArray[0])
                    print("✅ VAD Probability (\(name)): \(probability)")
                    return min(max(probability, 0), 1)
                }
            }
            
            // Print available outputs for debugging
            print("❌ Could not find probability output")
            for name in decoderResult.featureNames {
                print("Available Decoder output: \(name)")
            }
            
        } catch {
            print("❌ Model error: \(error)")
        }
        
        return fallbackVAD(audioChunk)
    }
    
    private func fallbackVAD(_ chunk: [Float]) -> Float {
        // More sophisticated energy-based VAD for noisy environments
        var rms: Float = 0
        vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
        
        // Calculate zero crossing rate
        var zcr: Float = 0
        for i in 1..<chunk.count {
            if (chunk[i] > 0 && chunk[i-1] < 0) || (chunk[i] < 0 && chunk[i-1] > 0) {
                zcr += 1
            }
        }
        zcr = zcr / Float(chunk.count - 1)
        
        // Higher thresholds for noisy environments
        let energyThreshold: Float = 0.02  // Increased from 0.01
        let zcrLow: Float = 0.05   // Speech typically has moderate ZCR
        let zcrHigh: Float = 0.25  // Too high ZCR often indicates noise
        
        var probability: Float = 0
        
        // Only consider it speech if energy is high enough AND ZCR is in speech range
        if rms > energyThreshold {
            if zcr > zcrLow && zcr < zcrHigh {
                // Likely speech - scale more conservatively
                probability = min(rms * 20, 0.9)  // Reduced from 30
            } else if zcr <= zcrLow {
                // Very low ZCR might be low frequency noise
                probability = min(rms * 5, 0.2)
            } else {
                // High ZCR is typically noise
                probability = 0.0
            }
        }
        
        return probability
    }
}