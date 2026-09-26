//
//  LaunchAtLoginManager.swift
//  rsync
//
//  Manages launching at login using macOS SMAppService (App bundle)
//  with automatic fallback to ~/Library/LaunchAgents for CLI/development builds.
//

import Foundation
import ServiceManagement
import AppKit

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    private let launchAgentLabel = "com.saihgupr.rsync"
    
    @Published var isEnabled: Bool = false
    @Published var requiresApproval: Bool = false
    @Published var statusDescription: String = ""
    
    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }
    
    private var isBundledApp: Bool {
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            return Bundle.main.bundleURL.pathExtension == "app"
        }
        return false
    }
    
    private init() {
        refreshStatus()
    }
    
    /// Checks the current system status and updates published properties
    func refreshStatus() {
        if isBundledApp {
            let service = SMAppService.mainApp
            switch service.status {
            case .enabled:
                isEnabled = true
                requiresApproval = false
                statusDescription = "Enabled via macOS Login Items"
            case .requiresApproval:
                isEnabled = true
                requiresApproval = true
                statusDescription = "Requires approval in System Settings"
            case .notRegistered:
                let agentExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
                isEnabled = agentExists
                requiresApproval = false
                statusDescription = agentExists ? "Enabled via LaunchAgent" : "Disabled"
            case .notFound:
                let agentExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
                isEnabled = agentExists
                requiresApproval = false
                statusDescription = agentExists ? "Enabled via LaunchAgent" : "Disabled"
            @unknown default:
                isEnabled = false
                requiresApproval = false
                statusDescription = "Unknown"
            }
        } else {
            let agentExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
            isEnabled = agentExists
            requiresApproval = false
            statusDescription = agentExists ? "Enabled via LaunchAgent" : "Disabled"
        }
    }
    
    /// Enable or disable launch at login
    @discardableResult
    func setEnabled(_ enable: Bool) -> Bool {
        if enable {
            return enableLaunchAtLogin()
        } else {
            return disableLaunchAtLogin()
        }
    }
    
    private func enableLaunchAtLogin() -> Bool {
        if isBundledApp {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    refreshStatus()
                    return true
                }
                
                try service.register()
                refreshStatus()
                
                // If SMAppService succeeded or requires approval, remove any fallback LaunchAgent
                if service.status == .enabled || service.status == .requiresApproval {
                    removeLaunchAgent()
                    return true
                }
            } catch {
                print("LaunchAtLoginManager: SMAppService register failed: \(error). Falling back to LaunchAgent...")
            }
        }
        
        // Fallback or unbundled: Use LaunchAgent
        let success = installLaunchAgent()
        refreshStatus()
        return success
    }
    
    private func disableLaunchAtLogin() -> Bool {
        var smSuccess = true
        if isBundledApp {
            do {
                let service = SMAppService.mainApp
                if service.status != .notRegistered {
                    try service.unregister()
                }
            } catch {
                print("LaunchAtLoginManager: SMAppService unregister failed: \(error)")
                smSuccess = false
            }
        }
        
        removeLaunchAgent()
        refreshStatus()
        return smSuccess
    }
    
    /// Opens macOS System Settings directly to Login Items
    func openSystemSettingsLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - LaunchAgent Helper (Fallback / Standalone)
    
    private func installLaunchAgent() -> Bool {
        let arguments: [String]
        
        if isBundledApp {
            arguments = ["/usr/bin/open", "-a", Bundle.main.bundlePath]
        } else {
            if let binPath = Bundle.main.executablePath ?? CommandLine.arguments.first {
                let executablePath = (binPath as NSString).standardizingPath
                arguments = [executablePath]
            } else {
                print("LaunchAtLoginManager: Unable to determine executable path")
                return false
            }
        }
        
        let plistData: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
        
        let agentDir = launchAgentURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plistData, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
            
            // Register with launchctl
            let uid = getuid()
            let bootstrapProcess = Process()
            bootstrapProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootstrapProcess.arguments = ["bootstrap", "gui/\(uid)", launchAgentURL.path]
            try? bootstrapProcess.run()
            bootstrapProcess.waitUntilExit()
            
            print("LaunchAtLoginManager: Installed LaunchAgent at \(launchAgentURL.path)")
            return true
        } catch {
            print("LaunchAtLoginManager: Failed to install LaunchAgent: \(error)")
            return false
        }
    }
    
    private func removeLaunchAgent() {
        guard FileManager.default.fileExists(atPath: launchAgentURL.path) else { return }
        
        let uid = getuid()
        let bootoutProcess = Process()
        bootoutProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootoutProcess.arguments = ["bootout", "gui/\(uid)/\(launchAgentLabel)"]
        try? bootoutProcess.run()
        bootoutProcess.waitUntilExit()
        
        try? FileManager.default.removeItem(at: launchAgentURL)
        print("LaunchAtLoginManager: Removed LaunchAgent at \(launchAgentURL.path)")
    }
}
