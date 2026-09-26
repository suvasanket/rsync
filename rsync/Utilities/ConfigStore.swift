//
//  ConfigStore.swift
//  rsync
//
//  Persists folders, settings, and rclone configurations to a dedicated
//  hidden directory in the user's home directory (~/.rsync by default).
//

import Foundation

struct StoredConfig: Codable {
    var version: Int = 1
    var settings: AppSettings
    var folders: [SyncFolder]
}

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()
    
    private let pointerFileName = ".rsync_config_dir"
    private let defaultDirectoryName = ".rsync"
    private let configFileName = "config.json"
    private let rcloneFileName = "rclone.conf"
    private let lock = NSLock()
    
    private var customConfigDirectory: URL?
    
    private init() {
        // Ensure config directory and rclone.conf exist
        _ = configDirectoryURL
        ensureRcloneConfigExists()
    }
    
    // MARK: - Directory Resolution
    
    /// The root hidden configuration directory
    var configDirectoryURL: URL {
        lock.lock()
        defer { lock.unlock() }
        
        if let custom = customConfigDirectory {
            return custom
        }
        
        // 1. Environment variable override
        if let envPath = ProcessInfo.processInfo.environment["RSYNC_CONFIG_DIR"], !envPath.isEmpty {
            let expanded = (envPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            customConfigDirectory = url
            return url
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pointerFile = home.appendingPathComponent(pointerFileName)
        
        // 2. Pointer file in home (~/.rsync_config_dir)
        if FileManager.default.fileExists(atPath: pointerFile.path),
           let savedPath = try? String(contentsOf: pointerFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !savedPath.isEmpty {
            let expanded = (savedPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            customConfigDirectory = url
            return url
        }
        
        // 3. Default: ~/.rsync
        let defaultDir = home.appendingPathComponent(defaultDirectoryName, isDirectory: true)
        return defaultDir
    }
    
    /// Path to config.json
    var configURL: URL {
        configDirectoryURL.appendingPathComponent(configFileName)
    }
    
    /// Path to rclone.conf
    var rcloneConfigURL: URL {
        configDirectoryURL.appendingPathComponent(rcloneFileName)
    }
    
    static var staticConfigDirectoryURL: URL {
        shared.configDirectoryURL
    }
    
    static var staticConfigURL: URL {
        shared.configURL
    }
    
    static var staticRcloneConfigURL: URL {
        shared.rcloneConfigURL
    }
    
    // MARK: - rclone.conf Management
    
    /// Ensures that an rclone.conf file exists inside the config directory.
    /// If none exists, attempts to import any existing ~/.config/rclone/rclone.conf.
    func ensureRcloneConfigExists() {
        let rcloneConf = rcloneConfigURL
        if !FileManager.default.fileExists(atPath: rcloneConf.path) {
            let parent = rcloneConf.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            
            // Check default ~/.config/rclone/rclone.conf to import existing credentials
            let defaultRclone = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/rclone/rclone.conf")
            if FileManager.default.fileExists(atPath: defaultRclone.path) {
                do {
                    try FileManager.default.copyItem(at: defaultRclone, to: rcloneConf)
                    print("ConfigStore: Imported existing rclone.conf from \(defaultRclone.path) to \(rcloneConf.path)")
                } catch {
                    print("ConfigStore: Failed to copy existing rclone.conf: \(error)")
                }
            } else {
                FileManager.default.createFile(atPath: rcloneConf.path, contents: Data(), attributes: nil)
            }
        }
    }
    
    // MARK: - Changing Config Directory
    
    /// Changes the configuration directory to a new location, migrating existing files.
    func changeConfigDirectory(to newDirectory: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let oldDir = customConfigDirectory ?? (
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultDirectoryName, isDirectory: true)
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pointerFile = home.appendingPathComponent(pointerFileName)
        
        // Ensure new directory exists
        if !FileManager.default.fileExists(atPath: newDirectory.path) {
            try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        }
        
        // Copy config.json to new directory if old exists and new does not
        let oldConfig = oldDir.appendingPathComponent(configFileName)
        let newConfig = newDirectory.appendingPathComponent(configFileName)
        if FileManager.default.fileExists(atPath: oldConfig.path) && !FileManager.default.fileExists(atPath: newConfig.path) {
            try? FileManager.default.copyItem(at: oldConfig, to: newConfig)
        }
        
        // Copy rclone.conf to new directory if old exists and new does not
        let oldRclone = oldDir.appendingPathComponent(rcloneFileName)
        let newRclone = newDirectory.appendingPathComponent(rcloneFileName)
        if FileManager.default.fileExists(atPath: oldRclone.path) && !FileManager.default.fileExists(atPath: newRclone.path) {
            try? FileManager.default.copyItem(at: oldRclone, to: newRclone)
        }
        
        // Save pointer file
        try newDirectory.path.write(to: pointerFile, atomically: true, encoding: .utf8)
        
        // Update active directory
        customConfigDirectory = newDirectory
        ensureRcloneConfigExists()
        print("ConfigStore: Successfully changed config directory to \(newDirectory.path)")
    }
    
    /// Resets the configuration directory back to ~/.rsync
    func resetToDefaultDirectory() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pointerFile = home.appendingPathComponent(pointerFileName)
        try? FileManager.default.removeItem(at: pointerFile)
        
        lock.lock()
        customConfigDirectory = nil
        lock.unlock()
        
        let defaultDir = home.appendingPathComponent(defaultDirectoryName, isDirectory: true)
        try changeConfigDirectory(to: defaultDir)
    }
    
    // MARK: - Load & Save
    
    /// Load configuration from dotfile (with auto-migration from UserDefaults if dotfile doesn't exist)
    func load() -> (AppSettings, [SyncFolder]) {
        let url = configURL
        
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let config = try decoder.decode(StoredConfig.self, from: data)
                print("ConfigStore: Successfully loaded \(config.folders.count) folder(s) from \(url.path)")
                return (config.settings, config.folders)
            } catch {
                print("ConfigStore: Failed to decode \(url.path): \(error). Attempting backup...")
                let bakURL = url.appendingPathExtension("bak")
                if FileManager.default.fileExists(atPath: bakURL.path),
                   let bakData = try? Data(contentsOf: bakURL),
                   let config = try? JSONDecoder().decode(StoredConfig.self, from: bakData) {
                    print("ConfigStore: Successfully recovered \(config.folders.count) folder(s) from \(bakURL.path)")
                    return (config.settings, config.folders)
                }
            }
        }
        
        // Migration from legacy UserDefaults if present
        var initialSettings: AppSettings?
        var initialFolders: [SyncFolder]?
        
        if let settingsData = UserDefaults.standard.data(forKey: "DriveSync.Settings"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
            initialSettings = saved
        }
        
        if let foldersData = UserDefaults.standard.data(forKey: "DriveSync.Folders"),
           let saved = try? JSONDecoder().decode([SyncFolder].self, from: foldersData) {
            initialFolders = saved
        }
        
        let detectedRclone = AppSettings.detectRclonePath() ?? AppSettings.defaultRclonePath
        var settings = initialSettings ?? AppSettings(rclonePath: detectedRclone)
        settings.configDirectoryPath = configDirectoryURL.path
        settings.configFilePath = configURL.path
        let folders = initialFolders ?? []
        
        // Save initial dotfile immediately
        save(settings: settings, folders: folders)
        return (settings, folders)
    }
    
    /// Saves configuration atomically to the dotfile
    func save(settings: AppSettings, folders: [SyncFolder]) {
        let dir = configDirectoryURL
        let file = configURL
        let bak = file.appendingPathExtension("bak")
        
        do {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            
            // Backup existing file before overwrite
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.removeItem(at: bak)
                try? FileManager.default.copyItem(at: file, to: bak)
            }
            
            var updatedSettings = settings
            updatedSettings.configDirectoryPath = dir.path
            updatedSettings.configFilePath = file.path
            
            let config = StoredConfig(version: 1, settings: updatedSettings, folders: folders)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(config)
            
            try data.write(to: file, options: .atomic)
            print("ConfigStore: Successfully saved \(folders.count) folder(s) to \(file.path)")
        } catch {
            print("ConfigStore: Error writing config to \(file.path): \(error)")
        }
    }
}
