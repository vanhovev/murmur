//
//  ContentView.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
//

import SwiftUI
import WhisperKit
import AVFoundation
import CoreML
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var modelStorage: String = "huggingface/models/argmaxinc/whisperkit-coreml"
    @AppStorage("selectedAudioInput") private var selectedAudioInput: String = "No Audio Input"
    
    @ObservedObject var model: Model
    @State private var transcription: String = ""
    @State private var loadingProgressValue: Float = 0.0
    @State private var isTranscribing: Bool = false
    @State private var transcribeTask: Task<Void, Never>?
    @State private var toggleIcon = false
    
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isTranscribing ? Color.green.opacity(0.2) : model.modelState == .loaded ? Color.gray.opacity(0.2) : Color.red.opacity(0.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding([.top, .leading, .trailing])
                .padding(.bottom, 10)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    if let provider = providers.first {
                        provider.loadObject(ofClass: URL.self) { url, _ in
                            if let audioURL = url as? URL {
                                self.transcribeAudio(from: audioURL)
                            }
                        }
                    }
                    return true
                }
                .overlay(
                    VStack {
                            if !transcription.isEmpty {
                                Text(transcription)
                                    .padding(25.0)
                                Spacer()
                            } else {
                                Image(systemName: "arrow.down.document")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.secondary)
                                    .symbolEffect(.wiggle, options: .speed(0.1))
                            }
                    }
                )
                
            
            Spacer()
            
            VStack {
                HStack {
                    Text(model.selectedModel)
                    Text("•")
                    Text(model.selectedLanguage)
                    Text("•")
                    Text(model.modelState.description)
                }
                HStack {
                    Text(WhisperKit.deviceName())
                    Text("•")
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                }
            }
            .padding(.bottom)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            
            if let whisperKit = model.whisperKit,
               isTranscribing,
               let task = transcribeTask,
               !task.isCancelled,
               whisperKit.progress.fractionCompleted < 1
            {
                HStack {
                    ProgressView(whisperKit.progress)
                        .progressViewStyle(.linear)
                        .labelsHidden()
                        .padding(.horizontal)
                    
                    Button {
                        transcribeTask?.cancel()
                        transcribeTask = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func transcribeAudio(from audioURL: URL) {
        print(audioURL)
        Task {
            await MainActor.run {
                isTranscribing = true
            }
            do {
                print(model.whisperKit ?? "null")
                guard let whisperKit = model.whisperKit else {
                    self.transcription = "Not loaded"
                    return
                }
                
                let languageCode = Constants.languages[model.selectedLanguage, default: Constants.defaultLanguageCode]
                let options = DecodingOptions(
                    verbose: true,
                    task: .transcribe,
                    language: languageCode,
                    temperature: 0.0,
                    temperatureFallbackCount: 5,
                    sampleLength: 224,
                    usePrefillPrompt: true,
                    usePrefillCache: true,
                    skipSpecialTokens: false,
                    withoutTimestamps: false,
                    wordTimestamps: true,
                    chunkingStrategy: .vad
                )
                
                let transcriptionResults = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
                
                if let firstTranscription = transcriptionResults.first?.text {
                    self.transcription = firstTranscription
                } else {
                    self.transcription = "Aucune transcription disponible."
                }
            } catch {
                self.transcription = "Erreur lors de la transcription : \(error)"
            }
            
            await MainActor.run {
                isTranscribing = false
            }
        }
    }
    
    func updateProgressBar(targetProgress: Float, maxTime: TimeInterval) async {
        let initialProgress = loadingProgressValue
        let decayConstant = -log(1 - targetProgress) / Float(maxTime)
        
        let startTime = Date()
        
        while true {
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            let decayFactor = exp(-decayConstant * Float(elapsedTime))
            let progressIncrement = (1 - initialProgress) * (1 - decayFactor)
            let currentProgress = initialProgress + progressIncrement
            
            await MainActor.run {
                loadingProgressValue = currentProgress
            }
            
            if currentProgress >= targetProgress {
                break
            }
            
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                break
            }
        }
    }
}

#Preview {
    @Previewable var model = Model()
    
    
    ContentView(model: model)
    //.modelContainer(for: Model.self, inMemory: true)
}
