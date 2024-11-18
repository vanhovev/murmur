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
    @Query private var items: [Item]

    @State private var transcription: String = ""
    @State private var availableModels: [String] = []
    @State private var availableLanguages: [String] = []
    @State private var modelState: ModelState = .unloaded
    @State private var loadingProgressValue: Float = 0.0
    @State private var whisperKit: WhisperKit?

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            VStack {
                Text("Glissez-déposez un fichier audio ici")

                List(availableModels, id: \.self) { model in
                    Button(model) {
                        loadModel(model)
                    }
                }

                Picker("Select Language", selection: $selectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()

                Text("Selected Model: \(selectedModel)")
                    .padding()

                Text("Selected Language: \(selectedLanguage)")
                    .padding()

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            Text("Glissez et déposez ici")
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

                if !transcription.isEmpty {
                    Text("Transcription:")
                    Text(transcription)
                        .padding()
                } else {
                    Text("Sélectionnez un fichier audio pour la transcription.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                fetchModels()
                fetchLanguages()
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }

    private func transcribeAudio(from audioURL: URL) {
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
    }

    private func fetchModels() {
        Task {
            do {
                let remoteModels = await WhisperKit.recommendedRemoteModels()
                availableModels = remoteModels.supported
                availableModels.append(contentsOf: localModels())
            }
        }
    }

    private func fetchLanguages() {
        availableLanguages = Constants.languages.map { $0.key }.sorted()
    }

    private func localModels() -> [String] {
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = documents.appendingPathComponent("whisper_models")
            if let downloadedModels = try? FileManager.default.contentsOfDirectory(atPath: modelPath.path) {
                return WhisperKit.formatModelFiles(downloadedModels)
            }
        }
        return []
    }

    private func loadModel(_ model: String) {
        print("Chargement du modèle \(model)")

        Task {
            do {
                let whisperKitConfig = WhisperKitConfig(model: model)

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
        .modelContainer(for: Item.self, inMemory: true)
}
