//
//  ContentView.swift
//  VAD-Test
//
//  Created by Elijah Arbee on 8/20/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vadManager = VADManager()
    @State private var animationScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Voice Activity Detection")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ZStack {
                Circle()
                    .fill(vadManager.isVoiceDetected ? Color.green.opacity(0.3) : Color.gray.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .scaleEffect(animationScale)
                    .animation(.easeInOut(duration: 0.3), value: vadManager.isVoiceDetected)
                
                Circle()
                    .fill(vadManager.isVoiceDetected ? Color.green : Color.gray)
                    .frame(width: 150, height: 150)
                
                Image(systemName: vadManager.isVoiceDetected ? "waveform" : "mic.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, value: vadManager.isVoiceDetected)
            }
            
            VStack(spacing: 10) {
                Text("Voice Probability")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ProgressView(value: vadManager.voiceProbability)
                    .progressViewStyle(LinearProgressViewStyle(tint: vadManager.isVoiceDetected ? .green : .gray))
                    .frame(width: 250)
                
                Text(String(format: "%.1f%%", vadManager.voiceProbability * 100))
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            VStack(spacing: 15) {
                if vadManager.isVoiceDetected {
                    Label("Voice Detected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)
                } else {
                    Label("No Voice", systemImage: "xmark.circle")
                        .foregroundColor(.gray)
                        .font(.headline)
                }
                
                Button(action: {
                    if vadManager.isRecording {
                        vadManager.stopRecording()
                    } else {
                        vadManager.startRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: vadManager.isRecording ? "stop.fill" : "play.fill")
                        Text(vadManager.isRecording ? "Stop Recording" : "Start Recording")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(vadManager.isRecording ? Color.red : Color.blue)
                    .cornerRadius(10)
                }
                
                if let error = vadManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            // Adjustable parameters section
            VStack(alignment: .leading, spacing: 10) {
                Text("Noise Adjustment")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading) {
                    Text("Threshold: \(String(format: "%.2f", vadManager.threshold))")
                        .font(.caption)
                    Slider(value: $vadManager.threshold, in: 0.3...0.9)
                        .tint(.blue)
                }
                
                VStack(alignment: .leading) {
                    Text("Min Speech Duration: \(vadManager.minSpeechDuration * 32)ms")
                        .font(.caption)
                    Slider(value: Binding(
                        get: { Double(vadManager.minSpeechDuration) },
                        set: { vadManager.minSpeechDuration = Int($0) }
                    ), in: 3...15)
                    .tint(.green)
                }
                
                HStack {
                    Button("Quiet") {
                        vadManager.threshold = 0.3
                        vadManager.minSpeechDuration = 5
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Moderate") {
                        vadManager.threshold = 0.5
                        vadManager.minSpeechDuration = 8
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Noisy") {
                        vadManager.threshold = 0.7
                        vadManager.minSpeechDuration = 12
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
        .padding()
        .onChange(of: vadManager.isVoiceDetected) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    animationScale = 1.2
                }
                withAnimation(.easeInOut(duration: 0.2).delay(0.2)) {
                    animationScale = 1.0
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
