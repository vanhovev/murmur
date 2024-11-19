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
    @State private var modelState: ModelState = .unloaded
    @State private var loadingProgressValue: Float = 0.0
    @State private var whisperKit: WhisperKit?
    @State private var inProgress: Bool = false

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
                    Text(transcription)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .top)
                )

            Spacer()

            HStack {
                Text(model.selectedModel)
                Text("•")
                Text(model.selectedLanguage)
            }
            .padding(.bottom)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !model.selectedModel.isEmpty {
                model.loadModel(model.selectedModel)
            }
        }
    }

    private func transcribeAudio(from audioURL: URL) {
        print(audioURL)
        self.inProgress = true
        Task {
            do {
                guard let whisperKit = whisperKit else {
                    self.transcription = "Le modèle n'est pas chargé."
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
        }
        self.inProgress = false
    }
}

#Preview {
    @Previewable var model = Model()

    
    ContentView(model: model)
        //.modelContainer(for: Model.self, inMemory: true)
}
