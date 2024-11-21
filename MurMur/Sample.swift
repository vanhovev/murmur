//  For licensing see accompanying LICENSE.md file.
//  Copyright © 2024 Argmax, Inc. All rights reserved.

import SwiftUI
import WhisperKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import AVFoundation
import CoreML

struct Sample: View {
    @State private var whisperKit: WhisperKit?
    #if os(macOS)
    @State private var audioDevices: [AudioDevice]?
    #endif
    @State private var isRecording: Bool = false
    @State private var isTranscribing: Bool = false
    @State private var currentText: String = ""
    @State private var currentChunks: [Int: (chunkText: [String], fallbacks: Int)] = [:]
    // TODO: Make this configurable in the UI
    @State private var modelStorage: String = "huggingface/models/argmaxinc/whisperkit-coreml"
    @State private var appStartTime = Date()

    // MARK: Model management

    @State private var modelState: ModelState = .unloaded
    @State private var localModels: [String] = []
    @State private var localModelPath: String = ""
    @State private var availableModels: [String] = []
    @State private var availableLanguages: [String] = []
    @State private var disabledModels: [String] = WhisperKit.recommendedModels().disabled

    @AppStorage("selectedAudioInput") private var selectedAudioInput: String = "No Audio Input"
    @AppStorage("selectedModel") private var selectedModel: String = WhisperKit.recommendedModels().default
    @AppStorage("selectedTab") private var selectedTab: String = "Transcribe"
    @AppStorage("selectedTask") private var selectedTask: String = "transcribe"
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "english"
    @AppStorage("repoName") private var repoName: String = "argmaxinc/whisperkit-coreml"
    @AppStorage("enableTimestamps") private var enableTimestamps: Bool = true
    @AppStorage("enablePromptPrefill") private var enablePromptPrefill: Bool = true
    @AppStorage("enableCachePrefill") private var enableCachePrefill: Bool = true
    @AppStorage("enableSpecialCharacters") private var enableSpecialCharacters: Bool = false
    @AppStorage("enableEagerDecoding") private var enableEagerDecoding: Bool = false
    @AppStorage("enableDecoderPreview") private var enableDecoderPreview: Bool = true
    @AppStorage("temperatureStart") private var temperatureStart: Double = 0
    @AppStorage("fallbackCount") private var fallbackCount: Double = 5
    @AppStorage("compressionCheckWindow") private var compressionCheckWindow: Double = 60
    @AppStorage("sampleLength") private var sampleLength: Double = 224
    @AppStorage("silenceThreshold") private var silenceThreshold: Double = 0.3
    @AppStorage("realtimeDelayInterval") private var realtimeDelayInterval: Double = 1
    @AppStorage("useVAD") private var useVAD: Bool = true
    @AppStorage("tokenConfirmationsNeeded") private var tokenConfirmationsNeeded: Double = 2
    @AppStorage("concurrentWorkerCount") private var concurrentWorkerCount: Double = 4
    @AppStorage("chunkingStrategy") private var chunkingStrategy: ChunkingStrategy = .vad
    @AppStorage("encoderComputeUnits") private var encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("decoderComputeUnits") private var decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine

    // MARK: Standard properties

    @State private var loadingProgressValue: Float = 0.0
    @State private var specializationProgressRatio: Float = 0.7
    @State private var isFilePickerPresented = false
    @State private var modelLoadingTime: TimeInterval = 0
    @State private var firstTokenTime: TimeInterval = 0
    @State private var pipelineStart: TimeInterval = 0
    @State private var effectiveRealTimeFactor: TimeInterval = 0
    @State private var effectiveSpeedFactor: TimeInterval = 0
    @State private var totalInferenceTime: TimeInterval = 0
    @State private var tokensPerSecond: TimeInterval = 0
    @State private var currentLag: TimeInterval = 0
    @State private var currentFallbacks: Int = 0
    @State private var currentEncodingLoops: Int = 0
    @State private var currentDecodingLoops: Int = 0
    @State private var lastBufferSize: Int = 0
    @State private var lastConfirmedSegmentEndSeconds: Float = 0
    @State private var requiredSegmentsForConfirmation: Int = 4
    @State private var bufferEnergy: [Float] = []
    @State private var bufferSeconds: Double = 0
    @State private var confirmedSegments: [TranscriptionSegment] = []
    @State private var unconfirmedSegments: [TranscriptionSegment] = []

    // MARK: UI properties

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showComputeUnits: Bool = true
    @State private var showAdvancedOptions: Bool = false
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var selectedCategoryId: MenuItem.ID?
    @State private var transcribeTask: Task<Void, Never>?

    struct MenuItem: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var image: String
    }

    private var menu = [
        MenuItem(name: "Transcribe", image: "book.pages"),
        MenuItem(name: "Stream", image: "waveform.badge.mic"),
    ]

    private var isStreamMode: Bool {
        selectedCategoryId == menu.first(where: { $0.name == "Stream" })?.id
    }

    func getComputeOptions() -> ModelComputeOptions {
        return ModelComputeOptions(audioEncoderCompute: encoderComputeUnits, textDecoderCompute: decoderComputeUnits)
    }

    // MARK: Views

    func resetState() {
        transcribeTask?.cancel()
        isRecording = false
        isTranscribing = false
        whisperKit?.audioProcessor.stopRecording()
        currentText = ""
        currentChunks = [:]

        pipelineStart = Double.greatestFiniteMagnitude
        firstTokenTime = Double.greatestFiniteMagnitude
        effectiveRealTimeFactor = 0
        effectiveSpeedFactor = 0
        totalInferenceTime = 0
        tokensPerSecond = 0
        currentLag = 0
        currentFallbacks = 0
        currentEncodingLoops = 0
        currentDecodingLoops = 0
        lastBufferSize = 0
        lastConfirmedSegmentEndSeconds = 0
        requiredSegmentsForConfirmation = 2
        bufferEnergy = []
        bufferSeconds = 0
        confirmedSegments = []
        unconfirmedSegments = []
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading) {
                modelSelectorView
                    .padding(.vertical)
                computeUnitsView
                    .disabled(modelState != .loaded && modelState != .unloaded)
                    .padding(.bottom)

                List(menu, selection: $selectedCategoryId) { item in
                    HStack {
                        Image(systemName: item.image)
                        Text(item.name)
                            .font(.system(.title3))
                            .bold()
                    }
                }
                .onChange(of: selectedCategoryId) {
                    selectedTab = menu.first(where: { $0.id == selectedCategoryId })?.name ?? "Transcribe"
                }
                .disabled(modelState != .loaded)
                .foregroundColor(modelState != .loaded ? .secondary : .primary)

                Spacer()

                // New section for app and device info
                VStack(alignment: .leading, spacing: 4) {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                    Text("App Version: \(version) (\(build))")
                    #if os(iOS)
                    Text("Device Model: \(WhisperKit.deviceName())")
                    Text("OS Version: \(UIDevice.current.systemVersion)")
                    #elseif os(macOS)
                    Text("Device Model: \(WhisperKit.deviceName())")
                    Text("OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    #endif
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.vertical)
            }
            .navigationTitle("WhisperAX")
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            .padding(.horizontal)
            Spacer()
        } detail: {
            VStack {
                #if os(iOS)
                modelSelectorView
                    .padding()
                transcriptionView
                #elseif os(macOS)
                VStack(alignment: .leading) {
                    transcriptionView
                }
                .padding()
                #endif
                controlsView
            }
            .toolbar(content: {
                ToolbarItem {
                    Button {
                        if !enableEagerDecoding {
                            let fullTranscript = formatSegments(confirmedSegments + unconfirmedSegments, withTimestamps: enableTimestamps).joined(separator: "\n")
                            #if os(iOS)
                            UIPasteboard.general.string = fullTranscript
                            #elseif os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fullTranscript, forType: .string)
                            #endif
                        } else {
                            #if os(iOS)
                            UIPasteboard.general.string = confirmedText + hypothesisText
                            #elseif os(macOS)
                            NSPasteboard.general.clearContents()
                            #endif
                        }
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    .foregroundColor(.primary)
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            })
        }
        .onAppear {
            #if os(macOS)
            selectedCategoryId = menu.first(where: { $0.name == selectedTab })?.id
            #else
            if UIDevice.current.userInterfaceIdiom == .pad {
                selectedCategoryId = menu.first(where: { $0.name == selectedTab })?.id
            }
            #endif
            fetchModels()
        }
    }

    // MARK: - Transcription

    var transcriptionView: some View {
        VStack {
            if !bufferEnergy.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 1) {
                        let startIndex = max(bufferEnergy.count - 300, 0)
                        ForEach(Array(bufferEnergy.enumerated())[startIndex...], id: \.element) { _, energy in
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .frame(width: 2, height: CGFloat(energy) * 24)
                            }
                            .frame(maxHeight: 24)
                            .background(energy > Float(silenceThreshold) ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
                .frame(height: 24)
                .scrollIndicators(.never)
            }

            ScrollView {
                VStack(alignment: .leading) {
                        ForEach(Array(confirmedSegments.enumerated()), id: \.element) { _, segment in
                            let timestampText = enableTimestamps ? "[\(String(format: "%.2f", segment.start)) --> \(String(format: "%.2f", segment.end))]" : ""
                            Text(timestampText + segment.text)
                                .font(.headline)
                                .fontWeight(.bold)
                                .tint(.green)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(unconfirmedSegments.enumerated()), id: \.element) { _, segment in
                            let timestampText = enableTimestamps ? "[\(String(format: "%.2f", segment.start)) --> \(String(format: "%.2f", segment.end))]" : ""
                            Text(timestampText + segment.text)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if enableDecoderPreview {
                            Text("\(currentText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .defaultScrollAnchor(.bottom)
            .textSelection(.enabled)
            .padding()
            if let whisperKit,
               !isStreamMode,
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
    }

    // MARK: - Models

    var modelSelectorView: some View {
        Group {
            VStack {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(modelState == .loaded ? .green : (modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(.variableColor, isActive: modelState != .loaded && modelState != .unloaded)
                    Text(modelState.description)

                    Spacer()

                    if !availableModels.isEmpty {
                        Picker("", selection: $selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                HStack {
                                    let modelIcon = localModels.contains { $0 == model.description } ? "checkmark.circle" : "arrow.down.circle.dotted"
                                    Text("\(Image(systemName: modelIcon)) \(model.description.components(separatedBy: "_").dropFirst().joined(separator: " "))").tag(model.description)
                                }
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedModel, initial: false) { _, _ in
                            modelState = .unloaded
                        }
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                    }

                    Button(action: {
                        deleteModel()
                    }, label: {
                        Image(systemName: "trash")
                    })
                    .help("Delete model")
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(localModels.isEmpty)
                    .disabled(!localModels.contains(selectedModel))

                    #if os(macOS)
                    Button(action: {
                        let folderURL = whisperKit?.modelFolder ?? (localModels.contains(selectedModel) ? URL(fileURLWithPath: localModelPath) : nil)
                        if let folder = folderURL {
                            NSWorkspace.shared.open(folder)
                        }
                    }, label: {
                        Image(systemName: "folder")
                    })
                    .buttonStyle(BorderlessButtonStyle())
                    #endif
                    Button(action: {
                        if let url = URL(string: "https://huggingface.co/\(repoName)") {
                            #if os(macOS)
                            NSWorkspace.shared.open(url)
                            #else
                            UIApplication.shared.open(url)
                            #endif
                        }
                    }, label: {
                        Image(systemName: "link.circle")
                    })
                    .buttonStyle(BorderlessButtonStyle())
                }

                if modelState == .unloaded {
                    Divider()
                    Button {
                        resetState()
                        loadModel(selectedModel)
                        modelState = .loading
                    } label: {
                        Text("Load Model")
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                } else if loadingProgressValue < 1.0 {
                    VStack {
                        HStack {
                            ProgressView(value: loadingProgressValue, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(maxWidth: .infinity)

                            Text(String(format: "%.1f%%", loadingProgressValue * 100))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        if modelState == .prewarming {
                            Text("Specializing \(selectedModel) for your device...\nThis can take several minutes on first load")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }

    var computeUnitsView: some View {
        DisclosureGroup(isExpanded: $showComputeUnits) {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle((whisperKit?.audioEncoder as? WhisperMLModel)?.modelState == .loaded ? .green : (modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(.variableColor, isActive: modelState != .loaded && modelState != .unloaded)
                    Text("Audio Encoder")
                    Spacer()
                    Picker("", selection: $encoderComputeUnits) {
                        Text("CPU").tag(MLComputeUnits.cpuOnly)
                        Text("GPU").tag(MLComputeUnits.cpuAndGPU)
                        Text("Neural Engine").tag(MLComputeUnits.cpuAndNeuralEngine)
                    }
                    .onChange(of: encoderComputeUnits, initial: false) { _, _ in
                        loadModel(selectedModel)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle((whisperKit?.textDecoder as? WhisperMLModel)?.modelState == .loaded ? .green : (modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(.variableColor, isActive: modelState != .loaded && modelState != .unloaded)
                    Text("Text Decoder")
                    Spacer()
                    Picker("", selection: $decoderComputeUnits) {
                        Text("CPU").tag(MLComputeUnits.cpuOnly)
                        Text("GPU").tag(MLComputeUnits.cpuAndGPU)
                        Text("Neural Engine").tag(MLComputeUnits.cpuAndNeuralEngine)
                    }
                    .onChange(of: decoderComputeUnits, initial: false) { _, _ in
                        loadModel(selectedModel)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
            }
            .padding(.top)
        } label: {
            Button {
                showComputeUnits.toggle()
            } label: {
                Text("Compute Units")
                    .font(.headline)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Controls

    var audioDevicesView: some View {
        Group {
            #if os(macOS)
            HStack {
                if let audioDevices = audioDevices, !audioDevices.isEmpty {
                    Picker("", selection: $selectedAudioInput) {
                        ForEach(audioDevices, id: \.self) { device in
                            Text(device.name).tag(device.name)
                        }
                    }
                    .frame(width: 250)
                    .disabled(isRecording)
                }
            }
            .onAppear {
                audioDevices = AudioProcessor.getAudioDevices()
                if let audioDevices = audioDevices,
                   !audioDevices.isEmpty,
                   selectedAudioInput == "No Audio Input",
                   let device = audioDevices.first
                {
                    selectedAudioInput = device.name
                }
            }
            #endif
        }
    }

    var controlsView: some View {
        VStack {
            basicSettingsView

            if let selectedCategoryId, let item = menu.first(where: { $0.id == selectedCategoryId }) {
                switch item.name {
                    case "Transcribe":
                        VStack {
                            HStack {
                                Button {
                                    resetState()
                                } label: {
                                    Label("Reset", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)

                                Spacer()

                                audioDevicesView

                                Spacer()

                                Button {
                                    showAdvancedOptions.toggle()
                                } label: {
                                    Label("Settings", systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(.borderless)
                            }

                            HStack {
                                let color: Color = modelState != .loaded ? .gray : .red
                                Button(action: {
                                    withAnimation {
                                        selectFile()
                                    }
                                }) {
                                    Text("FROM FILE")
                                        .font(.headline)
                                        .foregroundColor(color)
                                        .padding()
                                        .cornerRadius(40)
                                        .frame(minWidth: 70, minHeight: 70)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 40)
                                                .stroke(color, lineWidth: 4)
                                        )
                                }
                                .fileImporter(
                                    isPresented: $isFilePickerPresented,
                                    allowedContentTypes: [.audio],
                                    allowsMultipleSelection: false,
                                    onCompletion: handleFilePicker
                                )
                                .lineLimit(1)
                                .contentTransition(.symbolEffect(.replace))
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(modelState != .loaded)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .padding()
                            }
                        }
                    default:
                        EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    var basicSettingsView: some View {
        VStack {
            HStack {
                Picker("", selection: $selectedTask) {
                    ForEach(DecodingTask.allCases, id: \.self) { task in
                        Text(task.description.capitalized).tag(task.description)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(!(whisperKit?.modelVariant.isMultilingual ?? false))
            }
            .padding(.horizontal)

            LabeledContent {
                Picker("", selection: $selectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(language.description).tag(language.description)
                    }
                }
                .disabled(!(whisperKit?.modelVariant.isMultilingual ?? false))
            } label: {
                Label("Source Language", systemImage: "globe")
            }
            .padding(.horizontal)
            .padding(.top)

            HStack {
                Text(effectiveRealTimeFactor.formatted(.number.precision(.fractionLength(3))) + " RTF")
                    .font(.system(.body))
                    .lineLimit(1)
                Spacer()
                #if os(macOS)
                Text(effectiveSpeedFactor.formatted(.number.precision(.fractionLength(1))) + " Speed Factor")
                    .font(.system(.body))
                    .lineLimit(1)
                Spacer()
                #endif
                Text(tokensPerSecond.formatted(.number.precision(.fractionLength(0))) + " tok/s")
                    .font(.system(.body))
                    .lineLimit(1)
                Spacer()
                Text("First token: " + (firstTokenTime - pipelineStart).formatted(.number.precision(.fractionLength(2))) + "s")
                    .font(.system(.body))
                    .lineLimit(1)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Logic

    func fetchModels() {
        availableModels = [selectedModel]

        // First check what's already downloaded
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = documents.appendingPathComponent(modelStorage).path

            // Check if the directory exists
            if FileManager.default.fileExists(atPath: modelPath) {
                localModelPath = modelPath
                do {
                    let downloadedModels = try FileManager.default.contentsOfDirectory(atPath: modelPath)
                    for model in downloadedModels where !localModels.contains(model) {
                        localModels.append(model)
                    }
                } catch {
                    print("Error enumerating files at \(modelPath): \(error.localizedDescription)")
                }
            }
        }

        localModels = WhisperKit.formatModelFiles(localModels)
        for model in localModels {
            if !availableModels.contains(model) {
                availableModels.append(model)
            }
        }

        print("Found locally: \(localModels)")
        print("Previously selected model: \(selectedModel)")

        Task {
            let remoteModelSupport = await WhisperKit.recommendedRemoteModels()
            await MainActor.run {
                for model in remoteModelSupport.supported {
                    if !availableModels.contains(model) {
                        availableModels.append(model)
                    }
                }
                for model in remoteModelSupport.disabled {
                    if !disabledModels.contains(model) {
                        disabledModels.append(model)
                    }
                }
            }
        }
    }

    func loadModel(_ model: String, redownload: Bool = false) {

        whisperKit = nil
        Task {
            let config = WhisperKitConfig(computeOptions: getComputeOptions(),
                                          verbose: true,
                                          logLevel: .debug,
                                          prewarm: false,
                                          load: false,
                                          download: false)
            whisperKit = try await WhisperKit(config)
            guard let whisperKit = whisperKit else {
                return
            }

            var folder: URL?

            // Check if the model is available locally
            if localModels.contains(model) && !redownload {
                // Get local model folder URL from localModels
                folder = URL(fileURLWithPath: localModelPath).appendingPathComponent(model)
            } else {
                // Download the model
                folder = try await WhisperKit.download(variant: model, from: repoName, progressCallback: { progress in
                    DispatchQueue.main.async {
                        loadingProgressValue = Float(progress.fractionCompleted) * specializationProgressRatio
                        modelState = .downloading
                    }
                })
            }

            await MainActor.run {
                loadingProgressValue = specializationProgressRatio
                modelState = .downloaded
            }

            if let modelFolder = folder {
                whisperKit.modelFolder = modelFolder

                await MainActor.run {
                    // Set the loading progress to 90% of the way after prewarm
                    loadingProgressValue = specializationProgressRatio
                    modelState = .prewarming
                }

                let progressBarTask = Task {
                    await updateProgressBar(targetProgress: 0.9, maxTime: 240)
                }

                // Prewarm models
                do {
                    try await whisperKit.prewarmModels()
                    progressBarTask.cancel()
                } catch {
                    print("Error prewarming models, retrying: \(error.localizedDescription)")
                    progressBarTask.cancel()
                    if !redownload {
                        loadModel(model, redownload: true)
                        return
                    } else {
                        // Redownloading failed, error out
                        modelState = .unloaded
                        return
                    }
                }

                await MainActor.run {
                    // Set the loading progress to 90% of the way after prewarm
                    loadingProgressValue = specializationProgressRatio + 0.9 * (1 - specializationProgressRatio)
                    modelState = .loading
                }

                try await whisperKit.loadModels()

                await MainActor.run {
                    if !localModels.contains(model) {
                        localModels.append(model)
                    }

                    availableLanguages = Constants.languages.map { $0.key }.sorted()
                    loadingProgressValue = 1.0
                    modelState = whisperKit.modelState
                }
            }
        }
    }

    func deleteModel() {
        if localModels.contains(selectedModel) {
            let modelFolder = URL(fileURLWithPath: localModelPath).appendingPathComponent(selectedModel)

            do {
                try FileManager.default.removeItem(at: modelFolder)

                if let index = localModels.firstIndex(of: selectedModel) {
                    localModels.remove(at: index)
                }

                modelState = .unloaded
            } catch {
                print("Error deleting model: \(error)")
            }
        }
    }

    func updateProgressBar(targetProgress: Float, maxTime: TimeInterval) async {
        let initialProgress = loadingProgressValue
        let decayConstant = -log(1 - targetProgress) / Float(maxTime)

        let startTime = Date()

        while true {
            let elapsedTime = Date().timeIntervalSince(startTime)

            // Break down the calculation
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

    func selectFile() {
        isFilePickerPresented = true
    }

    func handleFilePicker(result: Result<[URL], Error>) {
        switch result {
            case let .success(urls):
                guard let selectedFileURL = urls.first else { return }
                if selectedFileURL.startAccessingSecurityScopedResource() {
                    do {
                        // Access the document data from the file URL
                        let audioFileData = try Data(contentsOf: selectedFileURL)

                        // Create a unique file name to avoid overwriting any existing files
                        let uniqueFileName = UUID().uuidString + "." + selectedFileURL.pathExtension

                        // Construct the temporary file URL in the app's temp directory
                        let tempDirectoryURL = FileManager.default.temporaryDirectory
                        let localFileURL = tempDirectoryURL.appendingPathComponent(uniqueFileName)

                        // Write the data to the temp directory
                        try audioFileData.write(to: localFileURL)

                        print("File saved to temporary directory: \(localFileURL)")

                        transcribeFile(path: selectedFileURL.path)
                    } catch {
                        print("File selection error: \(error.localizedDescription)")
                    }
                }
            case let .failure(error):
                print("File selection error: \(error.localizedDescription)")
        }
    }

    func transcribeFile(path: String) {
        resetState()
        whisperKit?.audioProcessor = AudioProcessor()
        transcribeTask = Task {
            isTranscribing = true
            do {
                try await transcribeCurrentFile(path: path)
            } catch {
                print("File selection error: \(error.localizedDescription)")
            }
            isTranscribing = false
        }
    }

    func finalizeText() {
        // Finalize unconfirmed text
        Task {
            await MainActor.run {
                if !unconfirmedSegments.isEmpty {
                    confirmedSegments.append(contentsOf: unconfirmedSegments)
                    unconfirmedSegments = []
                }
            }
        }
    }

    // MARK: - Transcribe Logic

    func transcribeCurrentFile(path: String) async throws {
        // Load and convert buffer in a limited scope
        Logging.debug("Loading audio file: \(path)")
        let loadingStart = Date()
        let audioFileSamples = try await Task {
            try autoreleasepool {
                try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            }
        }.value
        Logging.debug("Loaded audio file in \(Date().timeIntervalSince(loadingStart)) seconds")

        let transcription = try await transcribeAudioSamples(audioFileSamples)

        await MainActor.run {
            currentText = ""
            guard let segments = transcription?.segments else {
                return
            }

            tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
            effectiveRealTimeFactor = transcription?.timings.realTimeFactor ?? 0
            effectiveSpeedFactor = transcription?.timings.speedFactor ?? 0
            currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
            firstTokenTime = transcription?.timings.firstTokenTime ?? 0
            modelLoadingTime = transcription?.timings.modelLoading ?? 0
            pipelineStart = transcription?.timings.pipelineStart ?? 0
            currentLag = transcription?.timings.decodingLoop ?? 0

            confirmedSegments = segments
        }
    }
    
    func transcribeAudioSamples(_ samples: [Float]) async throws -> TranscriptionResult? {
            guard let whisperKit = whisperKit else { return nil }

            let languageCode = Constants.languages[selectedLanguage, default: Constants.defaultLanguageCode]
            let task: DecodingTask = selectedTask == "transcribe" ? .transcribe : .translate
            let seekClip: [Float] = [lastConfirmedSegmentEndSeconds]

            let options = DecodingOptions(
                verbose: true,
                task: task,
                language: languageCode,
                temperature: Float(temperatureStart),
                temperatureFallbackCount: Int(fallbackCount),
                sampleLength: Int(sampleLength),
                usePrefillPrompt: enablePromptPrefill,
                usePrefillCache: enableCachePrefill,
                skipSpecialTokens: !enableSpecialCharacters,
                withoutTimestamps: !enableTimestamps,
                wordTimestamps: true,
                clipTimestamps: seekClip,
                concurrentWorkerCount: Int(concurrentWorkerCount),
                chunkingStrategy: chunkingStrategy
            )

            // Early stopping checks
            let decodingCallback: ((TranscriptionProgress) -> Bool?) = { (progress: TranscriptionProgress) in
                DispatchQueue.main.async {
                    let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                    let chunkId = isStreamMode ? 0 : progress.windowId

                    // First check if this is a new window for the same chunk, append if so
                    var updatedChunk = (chunkText: [progress.text], fallbacks: fallbacks)
                    if var currentChunk = currentChunks[chunkId], let previousChunkText = currentChunk.chunkText.last {
                        if progress.text.count >= previousChunkText.count {
                            // This is the same window of an existing chunk, so we just update the last value
                            currentChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress.text
                            updatedChunk = currentChunk
                        } else {
                            // This is either a new window or a fallback (only in streaming mode)
                            if fallbacks == currentChunk.fallbacks && isStreamMode {
                                // New window (since fallbacks havent changed)
                                updatedChunk.chunkText = [updatedChunk.chunkText.first ?? "" + progress.text]
                            } else {
                                // Fallback, overwrite the previous bad text
                                updatedChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress.text
                                updatedChunk.fallbacks = fallbacks
                                print("Fallback occured: \(fallbacks)")
                            }
                        }
                    }

                    // Set the new text for the chunk
                    currentChunks[chunkId] = updatedChunk
                    let joinedChunks = currentChunks.sorted { $0.key < $1.key }.flatMap { $0.value.chunkText }.joined(separator: "\n")

                    currentText = joinedChunks
                    currentFallbacks = fallbacks
                    currentDecodingLoops += 1
                }

                // Check early stopping
                let currentTokens = progress.tokens
                let checkWindow = Int(compressionCheckWindow)
                if currentTokens.count > checkWindow {
                    let checkTokens: [Int] = currentTokens.suffix(checkWindow)
                    let compressionRatio = compressionRatio(of: checkTokens)
                    if compressionRatio > options.compressionRatioThreshold! {
                        Logging.debug("Early stopping due to compression threshold")
                        return false
                    }
                }
                if progress.avgLogprob! < options.logProbThreshold! {
                    Logging.debug("Early stopping due to logprob threshold")
                    return false
                }
                return nil
            }

            let transcriptionResults: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: samples,
                decodeOptions: options,
                callback: decodingCallback
            )

            let mergedResults = mergeTranscriptionResults(transcriptionResults)

            return mergedResults
        }
}
