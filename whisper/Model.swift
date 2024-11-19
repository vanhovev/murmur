//
//  Model.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
//

import Foundation
import SwiftData
import WhisperKit
import SwiftUI

final class Model: ObservableObject {
    @Published var availableModels: [String] = []
    @AppStorage("selectedModel") var selectedModel: String = WhisperKit.recommendedModels().default
    @Published var availableLanguages: [String] = []
    @AppStorage("selectedLanguage") var selectedLanguage: String = "english"

    init() {
        fetchModels()
        fetchLanguages()
    }

    func fetchModels() {
        Task {
            do {
                let remoteModels = await WhisperKit.recommendedRemoteModels()
                let localModelsList = localModels()

                DispatchQueue.main.async {
                    self.availableModels = remoteModels.supported
                    self.availableModels.append(contentsOf: localModelsList)

                    if let selectedModel = self.availableModels.first(where: { $0 == self.selectedModel }) {
                        self.loadModel(selectedModel)
                    } else if let firstLocalModel = localModelsList.first {
                        self.selectedModel = firstLocalModel
                        self.loadModel(firstLocalModel)
                    }
                }
            }
        }
    }

    func fetchLanguages() {
        DispatchQueue.main.async {
            self.availableLanguages = Constants.languages.map { $0.key }.sorted()
        }
    }

    func localModels() -> [String] {
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

    func loadModel(_ model: String) {
        print("Chargement du modèle \(model)")

        Task {
            do {
                let computeOptions = ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
                let whisperKitConfig = WhisperKitConfig(model: model, computeOptions: computeOptions)
                let whisperKit = try await WhisperKit(whisperKitConfig)

                DispatchQueue.main.async {
                    print("Modèle \(model) chargé avec succès.")
                }
            } catch {
                DispatchQueue.main.async {
                    print("Erreur lors du chargement du modèle : \(error.localizedDescription)")
                }
            }
        }
    }
}
