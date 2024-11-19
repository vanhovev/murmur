//
//  whisperApp.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
//


import SwiftUI

@main
struct Border_BarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}


class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    //static private(set) var instance: AppDelegate!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var window: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        //AppDelegate.instance = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.target = self
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func handleClick(_ sender: NSButton) {
        let event = NSApp.currentEvent!
        if event.type == NSEvent.EventType.rightMouseUp {
            // Handle right-click
            openMenu()
        } else {
            // Handle left-click
            openView()
        }
    }

    func openView() {
        if window == nil {
            let contentView = ContentView()
            let hostingController = NSHostingController(rootView: contentView)
            window = NSWindow(contentViewController: hostingController)
            window?.setContentSize(NSSize(width: 500, height: 350))
            window?.title = "Whisper"
            
            window?.level = .floating
            
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func openMenu() {
        let menu = NSMenu()
        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        let languageMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()

        let subMenuModelItem = NSMenuItem(title: "Sub Item", action: #selector(subMenuItemClicked(_:)), keyEquivalent: "")
        modelMenu.addItem(subMenuModelItem)
        
        let subMenuLanguageItem = NSMenuItem(title: "Sub Item Language", action: #selector(subMenuItemClicked(_:)), keyEquivalent: "")
        languageMenu.addItem(subMenuLanguageItem)

        modelMenuItem.submenu = modelMenu
        languageMenuItem.submenu = languageMenu
        menu.addItem(modelMenuItem)
        menu.addItem(languageMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)

        statusItem.menu = nil
    }

    @objc func subMenuItemClicked(_ sender: NSMenuItem) {
        print("Clicked Menu Item: \(sender.title)")
    }
}





/*
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
}*/
