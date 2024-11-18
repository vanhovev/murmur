//
//  whisperApp.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
//

import SwiftUI
import SwiftData

@main
struct whisperApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Model.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 500, minHeight: 350)
        }
        .modelContainer(sharedModelContainer)
    }
}
