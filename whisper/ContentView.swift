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
    @AppStorage("selectedModel") private var selectedModel: String = WhisperKit.recommendedModels().default
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "english"
    @Query private var model: [Model]
    
    @State private var transcription: String = ""
    @State private var availableModels: [String] = []
    @State private var availableLanguages: [String] = []
    @State private var modelState: ModelState = .unloaded
    @State private var loadingProgressValue: Float = 0.0
    @State private var whisperKit: WhisperKit?
    @State private var inProgress: Bool = false
    
    var body: some View {
        
        VStack {
            
            
            HStack {
                Picker("", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                .onChange(of: selectedModel) { newValue in
                    loadModel(selectedModel)
                }
                .disabled(inProgress)
                
                Picker("", selection: $selectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                .disabled(inProgress)
            }
            
            Spacer()
            
            
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .overlay(
                    Text(transcription)
                        .padding()
                )
            
            
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(inProgress ? 0.5 : 0.2))
                    .frame(maxWidth: 100.0, maxHeight: 50.0)
                    .overlay(
                        Image(systemName: "document.fill")
                            .foregroundColor(.gray)
                    )
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
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            fetchModels()
            fetchLanguages()
            if !selectedModel.isEmpty {
                loadModel(selectedModel)
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
                
                let languageCode = Constants.languages[selectedLanguage, default: Constants.defaultLanguageCode]
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
    
    private func fetchModels() {
        Task {
            do {
                let remoteModels = await WhisperKit.recommendedRemoteModels()
                availableModels = remoteModels.supported
                
                let localModelsList = localModels()
                availableModels.append(contentsOf: localModelsList)
                
                if let selectedModel = availableModels.first(where: { $0 == self.selectedModel }) {
                    loadModel(selectedModel)
                } else if let firstLocalModel = localModelsList.first {
                    self.selectedModel = firstLocalModel
                    loadModel(firstLocalModel)
                }
            }
        }
    }
    
    private func fetchLanguages() {
        availableLanguages = Constants.languages.map { $0.key }.sorted()
    }
    
    private func localModels() -> [String] {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = documentsDirectory.appendingPathComponent("whisper_models")
            do {
                if FileManager.default.fileExists(atPath: modelPath.path) {
                    let downloadedModels = try FileManager.default.contentsOfDirectory(atPath: modelPath.path)
                    return WhisperKit.formatModelFiles(downloadedModels)
                }
            } catch {
                print("Erreur lors de la lecture des modèles locaux : \(error)")
            }
        }
        return []
    }
    
    private func loadModel(_ model: String) {
        print("Chargement du modèle \(model)")
        
        Task {
            do {
                let computeOptions = ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
                let whisperKitConfig = WhisperKitConfig(model: model, computeOptions: computeOptions)
                whisperKit = try await WhisperKit(whisperKitConfig)
                
                print("Modèle \(model) chargé avec succès.")
            } catch {
                print("Erreur lors du chargement du modèle : \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Model.self, inMemory: true)
}
