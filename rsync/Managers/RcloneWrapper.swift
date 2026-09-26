//
//  RcloneWrapper.swift
//  rsync
//
//  Created by saihgupr on 2024-12-11.
//  Optimized on 2026-09-25.
//

import Foundation
import AppKit

enum BisyncMode {
    case normal
    case initial
    case resync
}

enum RcloneError: LocalizedError {
    case notInstalled
    case configurationFailed(String)
    case syncFailed(String)
    case bisyncNeedsResync(String)
    case invalidRemote(String)
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "rclone is not installed. Please install it via Homebrew: brew install rclone"
        case .configurationFailed(let message):
            return "Configuration failed: \(message)"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .bisyncNeedsResync(let message):
            return "Bi-Sync failed and requires a resync: \(message)"
        case .invalidRemote(let name):
            return "Invalid remote: \(name)"
        }
    }
}

struct RcloneRemote: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    
    var displayName: String {
        "\(name) (\(type))"
    }
    
    var providerIcon: String {
        switch type.lowercased() {
        case "drive": return "externaldrive.badge.icloud"
        case "mega": return "m.circle.fill"
        case "onedrive": return "cloud.fill"
        case "dropbox": return "shippingbox.fill"
        case "box": return "archivebox.fill"
        case "pcloud": return "p.circle.fill"
        case "webdav": return "network"
        case "s3": return "server.rack"
        case "b2": return "cylinder.split.1x2.fill"
        case "sftp": return "terminal.fill"
        case "protondrive": return "lock.shield.fill"
        default: return "externaldrive.fill"
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
    }
    
    static func == (lhs: RcloneRemote, rhs: RcloneRemote) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type
    }
}

struct RemotePingResult: Sendable, Equatable {
    let isSuccess: Bool
    let latencyMs: Int?
    let message: String
}

actor RcloneWrapper {
    private let rclonePath: String
    private let runner = ProcessRunner.shared
    
    private var configArgs: [String] {
        ["--config", ConfigStore.shared.rcloneConfigURL.path]
    }
    
    init(rclonePath: String = AppSettings.defaultRclonePath) {
        self.rclonePath = rclonePath
    }
    
    /// Cancel any currently running sync operation
    func cancelCurrentOperation() async {
        await runner.terminateCurrentProcess()
    }
    
    // MARK: - Connectivity / Ping Check
    
    /// Pings and verifies connectivity to a specific remote
    func pingRemote(name: String) async -> RemotePingResult {
        let startTime = Date()
        do {
            let result = try await runner.run(
                rclonePath,
                arguments: configArgs + [
                    "lsd",
                    "\(name):",
                    "--max-depth", "1",
                    "--contimeout", "6s",
                    "--timeout", "10s"
                ]
            )
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            if result.isSuccess {
                return RemotePingResult(
                    isSuccess: true,
                    latencyMs: latency,
                    message: "Connected (\(latency)ms)"
                )
            } else {
                let raw = result.stderr.isEmpty ? result.stdout : result.stderr
                let clean = raw.components(separatedBy: "\n")
                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Connection failed"
                return RemotePingResult(
                    isSuccess: false,
                    latencyMs: latency,
                    message: clean
                )
            }
        } catch {
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            return RemotePingResult(
                isSuccess: false,
                latencyMs: latency,
                message: error.localizedDescription
            )
        }
    }
    
    /// Ensures the destination remote folder exists prior to syncing
    func ensureRemoteDirectoryExists(_ remotePath: String) async {
        let parts = remotePath.components(separatedBy: ":")
        if parts.count >= 2 {
            let subPath = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            if !subPath.isEmpty {
                _ = try? await runner.run(rclonePath, arguments: configArgs + ["mkdir", remotePath])
            }
        }
    }
    
    // MARK: - Installation Check
    
    func isInstalled() async -> Bool {
        do {
            let result = try await runner.run(rclonePath, arguments: ["version"])
            return result.isSuccess
        } catch {
            return false
        }
    }
    
    func version() async throws -> String {
        let result = try await runner.run(rclonePath, arguments: ["version"])
        guard result.isSuccess else {
            throw RcloneError.notInstalled
        }
        return result.stdout.components(separatedBy: "\n").first ?? result.stdout
    }
    
    // MARK: - Remote Management (Google Drive)
    
    func listRemotes() async throws -> [RcloneRemote] {
        let result = try await runner.run(rclonePath, arguments: configArgs + ["listremotes", "--long"])
        guard result.isSuccess else {
            throw RcloneError.configurationFailed(result.stderr)
        }
        
        var remotes: [RcloneRemote] = []
        let lines = result.stdout.components(separatedBy: "\n")
        
        for line in lines where !line.isEmpty {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2 {
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let type = parts[1].trimmingCharacters(in: .whitespaces)
                remotes.append(RcloneRemote(name: name, type: type))
            }
        }
        
        return remotes
    }
    
    /// Creates a new Google Drive remote using in-app browser OAuth flow
    func createDriveAccount(name: String, clientId: String? = nil, clientSecret: String? = nil) async throws {
        var extra: [String: String] = ["scope": "drive"]
        if let clientId = clientId, !clientId.isEmpty {
            extra["client_id"] = clientId
        }
        if let clientSecret = clientSecret, !clientSecret.isEmpty {
            extra["client_secret"] = clientSecret
        }
        try await createOAuthAccount(
            name: name,
            type: "drive",
            clientId: clientId,
            clientSecret: clientSecret,
            extraConfig: extra
        )
    }
    
    /// Generic OAuth account creator (Google Drive, OneDrive, Dropbox, Box, pCloud, etc.)
    func createOAuthAccount(
        name: String,
        type: String,
        clientId: String? = nil,
        clientSecret: String? = nil,
        extraConfig: [String: String] = [:]
    ) async throws {
        final class AuthState: @unchecked Sendable {
            private let lock = NSLock()
            private var _output = ""
            private var _opened = false
            
            func append(_ str: String) {
                lock.lock()
                defer { lock.unlock() }
                _output += str
            }
            
            func shouldOpenBrowser() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if !_opened {
                    _opened = true
                    return true
                }
                return false
            }
            
            var output: String {
                lock.lock()
                defer { lock.unlock() }
                return _output
            }
        }
        
        let state = AuthState()
        var authArgs = ["authorize", type]
        if let id = clientId, !id.trimmingCharacters(in: .whitespaces).isEmpty,
           let secret = clientSecret, !secret.trimmingCharacters(in: .whitespaces).isEmpty {
            authArgs.append(contentsOf: [id.trimmingCharacters(in: .whitespaces), secret.trimmingCharacters(in: .whitespaces)])
        }
        
        let result = try await runner.runWithProgress(rclonePath, arguments: authArgs) { output in
            state.append(output)
            
            let pattern = #"http://127\.0\.0\.1:\d+/auth\S*"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 0), in: output),
               let url = URL(string: String(output[range])) {
                if state.shouldOpenBrowser() {
                    Task { @MainActor in
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        
        guard result.isSuccess else {
            throw RcloneError.configurationFailed("\(type) authentication was cancelled or failed.")
        }
        
        let combined = result.stdout.isEmpty ? state.output : result.stdout
        
        // Parse token JSON
        guard let tokenRange = combined.range(of: #"\{[\s\S]*"access_token"[\s\S]*\}"#, options: .regularExpression) else {
            throw RcloneError.configurationFailed("Did not receive a valid OAuth token. Please try again.")
        }
        
        let tokenJson = String(combined[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create remote in rclone config with the OAuth token and extra options
        var createArgs = configArgs + [
            "config", "create", name, type,
            "token", tokenJson
        ]
        
        for (key, val) in extraConfig {
            createArgs.append(contentsOf: [key, val])
        }
        
        let createResult = try await runner.run(rclonePath, arguments: createArgs)
        guard createResult.isSuccess else {
            throw RcloneError.configurationFailed("Failed to save remote config: \(createResult.stderr)")
        }
    }
    
    /// Creates a credential or key-based remote (MEGA, WebDAV, Nextcloud, S3, B2, SFTP, etc.)
    func createConfigAccount(
        name: String,
        type: String,
        options: [String: String]
    ) async throws {
        var createArgs = configArgs + ["config", "create", name, type, "--obscure"]
        
        for (k, v) in options {
            let key = k.trimmingCharacters(in: .whitespaces)
            let val = v.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !val.isEmpty {
                createArgs.append(contentsOf: [key, val])
            }
        }
        
        let result = try await runner.run(rclonePath, arguments: createArgs)
        guard result.isSuccess else {
            throw RcloneError.configurationFailed("Failed to configure remote '\(name)': \(result.stderr.isEmpty ? result.stdout : result.stderr)")
        }
    }
    
    /// Rename an existing remote across any provider type
    func renameRemote(from oldName: String, to newName: String) async throws {
        let dumpResult = try await runner.run(rclonePath, arguments: configArgs + ["config", "dump"])
        guard dumpResult.isSuccess,
              let data = dumpResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let remoteConfig = json[oldName],
              let type = remoteConfig["type"] as? String else {
            throw RcloneError.invalidRemote(oldName)
        }
        
        var createArgs = ["config", "create", newName, type, "--no-obscure"]
        for (key, val) in remoteConfig {
            if key == "type" { continue }
            if let stringVal = val as? String, !stringVal.isEmpty {
                createArgs.append(contentsOf: [key, stringVal])
            }
        }
        
        let createResult = try await runner.run(rclonePath, arguments: configArgs + createArgs)
        guard createResult.isSuccess else {
            throw RcloneError.configurationFailed("Failed to create new remote: \(createResult.stderr)")
        }
        
        let deleteResult = try await runner.run(rclonePath, arguments: configArgs + ["config", "delete", oldName])
        guard deleteResult.isSuccess else {
            _ = try? await runner.run(rclonePath, arguments: configArgs + ["config", "delete", newName])
            throw RcloneError.configurationFailed("Failed to delete old remote: \(deleteResult.stderr)")
        }
    }
    
    /// Delete a remote
    func deleteRemote(name: String) async throws {
        let result = try await runner.run(rclonePath, arguments: configArgs + ["config", "delete", name])
        guard result.isSuccess else {
            throw RcloneError.configurationFailed("Failed to delete remote: \(result.stderr)")
        }
    }
    
    /// Launch interactive rclone terminal wizard for all 40+ rclone providers
    nonisolated func openTerminalConfig() {
        let confPath = ConfigStore.shared.rcloneConfigURL.path
        let script = "tell application \"Terminal\" to do script \"'\(rclonePath)' config --config '\(confPath)'\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    
    // MARK: - Sync Operations
    
    func sync(
        source: String,
        destination: String,
        ignoredPatterns: [String] = [],
        dryRun: Bool = false,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> SyncResult {
        var args = configArgs + [
            "sync", source, destination,
            "--progress",
            "--stats-one-line",
            "--buffer-size", "4M",
            "--use-mmap"
        ]
        
        for pattern in ignoredPatterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                args.append(contentsOf: ["--exclude", trimmed])
            }
        }
        
        if dryRun {
            args.append("--dry-run")
        }
        
        let startTime = Date()
        
        let result: ProcessResult
        if let progressHandler = onProgress {
            result = try await runner.runWithProgress(rclonePath, arguments: args) { output in
                progressHandler(output)
            }
        } else {
            result = try await runner.run(rclonePath, arguments: args)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        if result.isSuccess {
            return SyncResult(
                success: true,
                filesTransferred: parseFileCount(from: result.stdout),
                bytesTransferred: parseByteCount(from: result.stdout),
                duration: duration,
                error: nil
            )
        } else {
            throw RcloneError.syncFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
    
    func bidirectionalSync(
        local: String,
        remote: String,
        ignoredPatterns: [String] = [],
        mode: BisyncMode,
        dryRun: Bool = false,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> SyncResult {
        var args = configArgs + [
            "bisync",
            local,
            remote,
            "--progress",
            "--stats-one-line",
            "--buffer-size", "4M",
            "--use-mmap",
            "--resilient",
            "--recover",
            "--max-lock", "2m",
            "--conflict-resolve", "newer"
        ]

        if mode == .initial || mode == .resync {
            let resyncMode = remote.lowercased().hasPrefix("mega:") ? "path1" : "newer"
            args.append(contentsOf: ["--resync", "--resync-mode", resyncMode])
        }

        for pattern in ignoredPatterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                args.append(contentsOf: ["--exclude", trimmed])
            }
        }

        if dryRun {
            args.append("--dry-run")
        }

        let startTime = Date()
        let result: ProcessResult

        if let progressHandler = onProgress {
            result = try await runner.runWithProgress(rclonePath, arguments: args) { output in
                progressHandler(output)
            }
        } else {
            result = try await runner.run(rclonePath, arguments: args)
        }

        let duration = Date().timeIntervalSince(startTime)

        guard result.isSuccess else {
            let errorMessage = result.stderr.isEmpty ? result.stdout : result.stderr
            if result.exitCode == 7 ||
               errorMessage.localizedCaseInsensitiveContains("too many deletes") ||
               errorMessage.localizedCaseInsensitiveContains("must run --resync") ||
               errorMessage.localizedCaseInsensitiveContains("needs resync") ||
               errorMessage.localizedCaseInsensitiveContains("bisync aborted") {
                throw RcloneError.bisyncNeedsResync(errorMessage)
            }
            throw RcloneError.syncFailed(errorMessage)
        }

        let combinedOutput = result.stdout + "\n" + result.stderr

        return SyncResult(
            success: true,
            filesTransferred: parseFileCount(from: combinedOutput),
            bytesTransferred: parseByteCount(from: combinedOutput),
            duration: duration,
            error: nil
        )
    }

    // MARK: - Helpers
    
    private func parseFileCount(from output: String) -> Int {
        let pattern = #"Transferred:\s+(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            return Int(output[range]) ?? 0
        }
        return 0
    }
    
    private func parseByteCount(from output: String) -> Int64 {
        let pattern = #"Transferred:\s+([\d.]+)\s*(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let valueRange = Range(match.range(at: 1), in: output),
           let unitRange = Range(match.range(at: 2), in: output) {
            
            let valueStr = String(output[valueRange])
            let unitStr = String(output[unitRange]).lowercased()
            
            if let value = Double(valueStr) {
                let multiplier: Double
                switch unitStr {
                case "b": multiplier = 1
                case "k", "kib": multiplier = 1024
                case "m", "mib": multiplier = 1024 * 1024
                case "g", "gib": multiplier = 1024 * 1024 * 1024
                case "t", "tib": multiplier = 1024 * 1024 * 1024 * 1024
                default: multiplier = 1
                }
                return Int64(value * multiplier)
            }
        }
        return 0
    }
}

struct SyncResult {
    let success: Bool
    let filesTransferred: Int
    let bytesTransferred: Int64
    let duration: TimeInterval
    let error: String?
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }
}
