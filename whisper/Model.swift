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
    static let shared = Model()
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
                _ = try await WhisperKit(whisperKitConfig)
                
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
        
        menu.addItem(modelMenuItem)
        menu.addItem(languageMenuItem)
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
    
    func updateModelMenuState(_ menu: NSMenu) {
        if let modelMenu = menu.item(at: 0)?.submenu {
            for item in modelMenu.items {
                if let model = item.representedObject as? String {
                    item.state = (model == selectedModel) ? .on : .off
                }
            }
        }
    }
}
