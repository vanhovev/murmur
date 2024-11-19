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
    @State private var isTranscribing: Bool = false
    @State private var transcribeTask: Task<Void, Never>?
    @State private var toggleIcon = false
    
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
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
                                if(isTranscribing){
                                    Image(systemName: "waveform")
                                        .font(.system(size: 50))
                                        .foregroundStyle(.secondary)
                                        .symbolEffect(.variableColor)
                                } else{
                                    Image(systemName: "arrow.down.document")
                                        .font(.system(size: 50))
                                        .foregroundStyle(.secondary)
                                        .symbolEffect(.wiggle, options: .speed(0.1))
                                }
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
                
                print("START TRANSCRIBE")
                let transcriptionResults = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
                print("END TRANSCRIBE")
                
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
    
    private func clear() {
        transcription.removeAll()
    }
}

#Preview {
    @Previewable var model = Model()
    
    
    ContentView(model: model)
    //.modelContainer(for: Model.self, inMemory: true)
}
