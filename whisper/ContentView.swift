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
    @AppStorage("selectedAudioInput") private var selectedAudioInput: String = "No Audio Input"
    
    @ObservedObject var model: Model
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
                                model.transcribeAudio(from: audioURL)
                            }
                        }
                    }
                    return true
                }
                .overlay(
                    VStack {
                        if !model.transcription.isEmpty {
                            Text(model.transcription)
                                    .padding(25.0)
                                Spacer()
                            } else {
                                if(model.isTranscribing){
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
    
    
    private func clear() {
        model.transcription.removeAll()
    }
}

#Preview {
    @Previewable var model = Model()
    
    
    ContentView(model: model)
    //.modelContainer(for: Model.self, inMemory: true)
}
