//
//  whisperApp.swift
//  whisper
//
//  Created by Valentin Vanhove on 18/11/2024.
//


import SwiftUI

@main
struct whisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) var instance: AppDelegate!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var window: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppDelegate.instance = self

        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.target = self
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func handleClick(_ sender: NSButton) {
        let event = NSApp.currentEvent!
        if event.type == NSEvent.EventType.rightMouseUp {
            openMenu()
        } else {
            openView()
        }
    }

    func openView() {
        if window == nil {
            let contentView = ContentView(model: Model.shared)
            let hostingController = NSHostingController(rootView: contentView)
            window = NSWindow(contentViewController: hostingController)
            window?.setContentSize(NSSize(width: 500, height: 350))
            window?.title = "M-Whisper"
            window?.level = .floating
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func openMenu() {
        let menu = NSMenu()

        Model.shared.addElementOnMenu(menu: menu)
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
