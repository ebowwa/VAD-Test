//
//  AdaptiveVAD.swift
//  VAD-Test
//
//  Adaptive VAD that adjusts to different environments
//

import Foundation
import Accelerate

class AdaptiveVAD {
    // Environment profiles
    enum Environment {
        case quiet      // Home, office
        case moderate   // Coffee shop, street
        case noisy      // Restaurant, crowd
        case veryNoisy  // Concert, subway
        
        var threshold: Float {
            switch self {
            case .quiet:     return 0.4
            case .moderate:  return 0.6
            case .noisy:     return 0.75
            case .veryNoisy: return 0.85
            }
        }
        
        var energyThreshold: Float {
            switch self {
            case .quiet:     return 0.005
            case .moderate:  return 0.015
            case .noisy:     return 0.025
            case .veryNoisy: return 0.04
            }
        }
    }
    
    // Noise floor tracking
    private var noiseFloorHistory: [Float] = []
    private let noiseFloorWindowSize = 50  // ~1.6 seconds of history
    private var currentNoiseFloor: Float = 0.0
    
    // Environment detection
    private var currentEnvironment: Environment = .moderate
    private var environmentScores: [Environment: Float] = [:]
    
    // Calibration
    private var isCalibrating = false
    private var calibrationSamples: [Float] = []
    private let calibrationDuration = 30  // chunks (~1 second)
    
    func startCalibration() {
        isCalibrating = true
        calibrationSamples.removeAll()
        print("📊 Starting noise calibration...")
    }
    
    func processNoiseLevel(_ chunk: [Float]) -> (environment: Environment, noiseFloor: Float) {
        // Calculate RMS energy
        var rms: Float = 0
        vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
        
        // Update noise floor tracking
        noiseFloorHistory.append(rms)
        if noiseFloorHistory.count > noiseFloorWindowSize {
            noiseFloorHistory.removeFirst()
        }
        
        // Calculate current noise floor (20th percentile of recent samples)
        let sortedHistory = noiseFloorHistory.sorted()
        let percentileIndex = Int(Float(sortedHistory.count) * 0.2)
        currentNoiseFloor = sortedHistory[min(percentileIndex, sortedHistory.count - 1)]
        
        // Calibration mode
        if isCalibrating {
            calibrationSamples.append(rms)
            if calibrationSamples.count >= calibrationDuration {
                finishCalibration()
            }
        }
        
        // Detect environment based on noise floor
        detectEnvironment()
        
        return (currentEnvironment, currentNoiseFloor)
    }
    
    private func finishCalibration() {
        isCalibrating = false
        
        guard !calibrationSamples.isEmpty else { return }
        
        // Calculate statistics from calibration
        let sortedSamples = calibrationSamples.sorted()
        let median = sortedSamples[sortedSamples.count / 2]
        let p75 = sortedSamples[Int(Float(sortedSamples.count) * 0.75)]
        let p90 = sortedSamples[Int(Float(sortedSamples.count) * 0.90)]
        
        // Determine environment from calibration
        if median < 0.01 && p90 < 0.02 {
            currentEnvironment = .quiet
            print("🔇 Detected: Quiet environment")
        } else if median < 0.02 && p90 < 0.04 {
            currentEnvironment = .moderate
            print("🔊 Detected: Moderate noise environment")
        } else if median < 0.04 && p90 < 0.08 {
            currentEnvironment = .noisy
            print("📢 Detected: Noisy environment")
        } else {
            currentEnvironment = .veryNoisy
            print("🔔 Detected: Very noisy environment")
        }
        
        calibrationSamples.removeAll()
    }
    
    private func detectEnvironment() {
        // Auto-detect environment based on running noise floor
        if currentNoiseFloor < 0.008 {
            currentEnvironment = .quiet
        } else if currentNoiseFloor < 0.018 {
            currentEnvironment = .moderate
        } else if currentNoiseFloor < 0.035 {
            currentEnvironment = .noisy
        } else {
            currentEnvironment = .veryNoisy
        }
    }
    
    func adjustProbability(_ rawProbability: Float, rmsEnergy: Float) -> Float {
        // Adjust probability based on signal-to-noise ratio
        let snr = rmsEnergy / max(currentNoiseFloor, 0.001)
        
        // Only consider it speech if it's significantly above noise floor
        let snrThreshold: Float = {
            switch currentEnvironment {
            case .quiet:     return 2.0   // 2x noise floor
            case .moderate:  return 2.5   // 2.5x noise floor
            case .noisy:     return 3.0   // 3x noise floor
            case .veryNoisy: return 4.0   // 4x noise floor
            }
        }()
        
        if snr < snrThreshold {
            // Signal is too close to noise floor
            return rawProbability * 0.3  // Heavily reduce probability
        }
        
        // Boost probability if signal is well above noise
        let snrBoost = min((snr / snrThreshold) - 1.0, 1.0)
        return min(rawProbability + (snrBoost * 0.2), 1.0)
    }
    
    func getCurrentThreshold() -> Float {
        return currentEnvironment.threshold
    }
    
    func getEnvironmentInfo() -> String {
        switch currentEnvironment {
        case .quiet:
            return "🔇 Quiet"
        case .moderate:
            return "🔊 Moderate"
        case .noisy:
            return "📢 Noisy"
        case .veryNoisy:
            return "🔔 Very Noisy"
        }
    }
}