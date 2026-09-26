//
//  AppSettings.swift
//  rsync
//
//  Created by saihgupr on 2024-12-11.
//  Updated on 2026-09-25.
//

import Foundation

enum SyncInterval: Codable, Equatable, Hashable, CaseIterable {
    case manual
    case minutes15
    case minutes30
    case hourly
    case daily
    case custom(minutes: Int)
    
    static var allCases: [SyncInterval] {
        [.manual, .minutes15, .minutes30, .hourly, .daily]
    }
    
    var displayName: String {
        switch self {
        case .manual: return "Manual / Off"
        case .minutes15: return "Every 15 minutes"
        case .minutes30: return "Every 30 minutes"
        case .hourly: return "Every Hour"
        case .daily: return "Once a Day"
        case .custom(let minutes): return "Every \(minutes) minutes"
        }
    }
    
    var intervalSeconds: TimeInterval? {
        switch self {
        case .manual: return nil
        case .minutes15: return 15 * 60
        case .minutes30: return 30 * 60
        case .hourly: return 60 * 60
        case .daily: return 24 * 60 * 60
        case .custom(let minutes): return TimeInterval(minutes * 60)
        }
    }
}

struct AppSettings: Codable, Equatable {
    var syncInterval: SyncInterval
    var rclonePath: String
    var showNotifications: Bool
    var notifyOnError: Bool
    var launchAtLogin: Bool
    var syncOnLaunch: Bool
    var dailySyncTime: Date
    var watchForChanges: Bool
    var debounceDelaySeconds: Double
    var syncOnFirstConnection: Bool
    var configFilePath: String
    var configDirectoryPath: String
    
    static let defaultRclonePath = "/opt/homebrew/bin/rclone"
    static let intelRclonePath = "/usr/local/bin/rclone"
    
    /// Default sync time: 9:00 AM
    static var defaultDailySyncTime: Date {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }
    
    init(
        syncInterval: SyncInterval = .manual,
        rclonePath: String = AppSettings.defaultRclonePath,
        showNotifications: Bool = true,
        notifyOnError: Bool = true,
        launchAtLogin: Bool = false,
        syncOnLaunch: Bool = true,
        dailySyncTime: Date? = nil,
        watchForChanges: Bool = true,
        debounceDelaySeconds: Double = 2.0,
        syncOnFirstConnection: Bool = true,
        configFilePath: String = "~/.rsync/config.json",
        configDirectoryPath: String = "~/.rsync"
    ) {
        self.syncInterval = syncInterval
        self.rclonePath = rclonePath
        self.showNotifications = showNotifications
        self.notifyOnError = notifyOnError
        self.launchAtLogin = launchAtLogin
        self.syncOnLaunch = syncOnLaunch
        self.dailySyncTime = dailySyncTime ?? AppSettings.defaultDailySyncTime
        self.watchForChanges = watchForChanges
        self.debounceDelaySeconds = debounceDelaySeconds
        self.syncOnFirstConnection = syncOnFirstConnection
        self.configFilePath = configFilePath
        self.configDirectoryPath = configDirectoryPath
    }
    
    enum CodingKeys: String, CodingKey {
        case syncInterval
        case rclonePath
        case showNotifications
        case notifyOnError
        case launchAtLogin
        case syncOnLaunch
        case dailySyncTime
        case watchForChanges
        case debounceDelaySeconds
        case syncOnFirstConnection
        case configFilePath
        case configDirectoryPath
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.syncInterval = try container.decodeIfPresent(SyncInterval.self, forKey: .syncInterval) ?? .manual
        self.rclonePath = try container.decodeIfPresent(String.self, forKey: .rclonePath) ?? AppSettings.defaultRclonePath
        self.showNotifications = try container.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? true
        self.notifyOnError = try container.decodeIfPresent(Bool.self, forKey: .notifyOnError) ?? true
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.syncOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .syncOnLaunch) ?? true
        self.dailySyncTime = try container.decodeIfPresent(Date.self, forKey: .dailySyncTime) ?? AppSettings.defaultDailySyncTime
        self.watchForChanges = try container.decodeIfPresent(Bool.self, forKey: .watchForChanges) ?? true
        self.debounceDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .debounceDelaySeconds) ?? 2.0
        self.syncOnFirstConnection = try container.decodeIfPresent(Bool.self, forKey: .syncOnFirstConnection) ?? true
        self.configFilePath = try container.decodeIfPresent(String.self, forKey: .configFilePath) ?? "~/.rsync/config.json"
        self.configDirectoryPath = try container.decodeIfPresent(String.self, forKey: .configDirectoryPath) ?? "~/.rsync"
    }
    
    static func detectRclonePath() -> String? {
        // 1. Check for bundled rclone (Preferred)
        if let bundledPath = Bundle.main.path(forResource: "rclone", ofType: nil) {
            return bundledPath
        }
        
        // 2. Check common system locations
        let paths = [
            "/opt/homebrew/bin/rclone", // Apple Silicon Homebrew
            intelRclonePath,            // Intel Homebrew
            "/usr/bin/rclone",          // System
            "/opt/local/bin/rclone"     // MacPorts
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["rclone"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            // Ignore
        }
        
        return nil
    }
}
