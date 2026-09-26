//
//  SettingsWindowManager.swift
//  rsync
//
//  Provides reliable standalone window presentation for SettingsView
//  when running as an unbundled / Command Line binary.
//

import SwiftUI
import AppKit

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    
    private init() {}
    
    func show(syncManager: SyncManager) {
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let contentView = SettingsView()
            .environmentObject(syncManager)
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "rsync Settings"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.makeKeyAndOrderFront(nil)
        
        self.window = newWindow
    }
}
