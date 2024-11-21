//
//  Model.swift
//  MurMur
//
//  Created by Valentin Vanhove on 18/11/2024.
//

import Foundation
import SwiftData
import WhisperKit
import SwiftUI

final class Model: ObservableObject {
    static let shared = Model()
    @Published var whisperKit: WhisperKit?
    @Published var isTranscribing: Bool = false
    @Published var transcription: String = ""

    @Published var availableModels: [String] = ["openai_whisper-tiny", "openai_whisper-small", "openai_whisper-base"]
    @AppStorage("selectedModel") var selectedModel: String = "openai_whisper-tiny"

    @Published var availableLanguages: [String] = []
    @AppStorage("selectedLanguage") var selectedLanguage: String = "french"

    @Published var modelState: ModelState = .unloaded
    @Published private var modelStorage: String = "huggingface/models/argmaxinc/whisperkit-coreml"
    @AppStorage("repoName") private var repoName: String = "argmaxinc/whisperkit-coreml"

    @Published var localModels: [String] = []
    @Published private var localModelPath: String = ""

    init() {
        fetchModels()
        fetchLanguages()
    }

    func fetchLocalModels() async -> [String] {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = documentsDirectory.appendingPathComponent(modelStorage)
            print("modelPath \(modelPath)")
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

    func fetchModels() {
        Task {
            do {
                let localModelsList = await fetchLocalModels()

                await MainActor.run {
                    self.localModels = localModelsList
                    if let selectedModel = self.availableModels.first(where: { $0 == self.selectedModel }) {
                        self.loadModel(selectedModel)
                    } else if let firstLocalModel = self.localModels.first {
                        self.selectedModel = firstLocalModel
                        self.loadModel(firstLocalModel)
                    }
                }
            }
        }
    }

    func fetchLanguages() {
        Task {
            await MainActor.run {
                self.availableLanguages = Constants.languages.map { $0.key }.sorted()
            }
        }
    }

    func loadModel(_ model: String, redownload: Bool = false) {
        Task {
            await MainActor.run {
                whisperKit = nil
            }

            print("Starting WhisperKit")
            let computeOptions = ModelComputeOptions(
                audioEncoderCompute: .all,
                textDecoderCompute: .all
            )

            print("Choosing audio encoder")

            let config = WhisperKitConfig(computeOptions: computeOptions,
                                          verbose: true,
                                          logLevel: .debug,
                                          prewarm: false,
                                          load: false,
                                          download: false)

            do {
                let newWhisperKit = try await WhisperKit(config)
                await MainActor.run {
                    whisperKit = newWhisperKit
                }
                print("WhisperKit initialized successfully")
            } catch {
                print("Error initializing WhisperKit: \(error.localizedDescription)")
                return
            }

            print("WhisperKit started")

            var folder: URL?

            // Check if the model is available locally
            if localModels.contains(model) && !redownload {
                // Get local model folder URL from localModels
                print("is available locally")
                folder = URL(fileURLWithPath: localModelPath).appendingPathComponent(model)
            } else {
                // Download the model
                print("is not available locally, downloading")
                folder = try await WhisperKit.download(variant: model, from: repoName, progressCallback: { progress in
                    DispatchQueue.main.async {
                        print(progress)
                        self.modelState = .downloading
                    }
                })
            }

            print("Initializing modelToLoad")

            await MainActor.run {
                modelState = .downloaded
            }

            if let modelFolder = folder {
                await MainActor.run {
                    whisperKit!.modelFolder = modelFolder
                }

                await MainActor.run {
                    modelState = .prewarming
                }

                // Prewarm modelToLoad
                do {
                    try await whisperKit!.prewarmModels()
                } catch {
                    print("Error prewarming modelToLoad, retrying: \(error.localizedDescription)")
                    if !redownload {
                        loadModel(model, redownload: true)
                        return
                    } else {
                        // Redownloading failed, error out
                        await MainActor.run {
                            modelState = .unloaded
                        }
                        return
                    }
                }

                await MainActor.run {
                    modelState = .loading
                }

                try await whisperKit?.loadModels()

                await MainActor.run {
                    if !localModels.contains(model) {
                        localModels.append(model)
                    }

                    availableLanguages = Constants.languages.map { $0.key }.sorted()
                    modelState = whisperKit!.modelState
                }
            }
        }
        print("Finished loading model")
    }


    func transcribeAudio(from audioURL: URL) {
        print(audioURL)
        Task {
            await MainActor.run {
                isTranscribing = true
            }
            do {
                guard let whisperKit = whisperKit else {
                    await MainActor.run {
                        transcription = "Not loaded"
                    }
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

                print("START TRANSCRIBE")
                let transcriptionResults = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
                print("END TRANSCRIBE")

                if let firstTranscription = transcriptionResults.first?.text {
                    await MainActor.run {
                        self.transcription = firstTranscription
                    }
                } else {
                    await MainActor.run {
                        self.transcription = "Aucune transcription disponible."
                    }
                }
            } catch {
                await MainActor.run {
                    self.transcription = "Erreur lors de la transcription : \(error)"
                }
            }

            await MainActor.run {
                isTranscribing = false
            }
        }
    }

    func addElementOnMenu(menu: NSMenu) {
        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        let languageMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()

        for model in availableModels {
            let modelItem = NSMenuItem(title: model, action: #selector(modelMenuItemClicked(_:)), keyEquivalent: "")
            modelItem.representedObject = model
            modelItem.target = self

            if model == selectedModel {
                modelItem.state = .on
            } else {
                modelItem.state = .off
            }

            modelMenu.addItem(modelItem)
        }

        for language in availableLanguages {
            let languageItem = NSMenuItem(title: language, action: #selector(languageMenuItemClicked(_:)), keyEquivalent: "")
            languageItem.representedObject = language
            languageItem.target = self

            if language == selectedLanguage {
                languageItem.state = .on
            } else {
                languageItem.state = .off
            }

            languageMenu.addItem(languageItem)
        }

        modelMenuItem.submenu = modelMenu
        languageMenuItem.submenu = languageMenu
        
        let modelFolderItem = NSMenuItem(title: "MurMur Folder", action: #selector(openModelFolder), keyEquivalent: "")
        modelFolderItem.target = self

        menu.addItem(modelMenuItem)
        menu.addItem(languageMenuItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(modelFolderItem)
    }

    @objc func modelMenuItemClicked(_ sender: NSMenuItem) {
        if let model = sender.representedObject as? String {
            selectedModel = model
            loadModel(model)

            if let menu = sender.menu {
                updateModelMenuState(menu)
            }
        }
    }

    @objc func languageMenuItemClicked(_ sender: NSMenuItem) {
        if let language = sender.representedObject as? String {
            selectedLanguage = language
        }
    }
    
    @objc func openModelFolder() {
        let folderURL = whisperKit?.modelFolder ?? (localModels.contains(selectedModel) ? URL(fileURLWithPath: localModelPath) : nil)
        if let folder = folderURL {
            NSWorkspace.shared.open(folder)
        }
    }

    func updateModelMenuState(_ menu: NSMenu) {
        if let modelMenu = menu.item(at: 0)?.submenu {
            for item in modelMenu.items {
                if let model = item.representedObject as? String {
                    item.state = (model == selectedModel) ? .on : .off
                }
            }
        }
    }
    func clear() {
        DispatchQueue.main.async {
            self.transcription = ""
        }
        }
}
