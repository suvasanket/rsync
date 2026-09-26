//
//  RcloneWrapper.swift
//  GoogleDriveSync
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
    }
    
    static func == (lhs: RcloneRemote, rhs: RcloneRemote) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type
    }
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
    func createDriveAccount(name: String) async throws {
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
        
        let result = try await runner.runWithProgress(rclonePath, arguments: ["authorize", "drive"]) { output in
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
            throw RcloneError.configurationFailed("Google Drive authentication was cancelled or failed.")
        }
        
        let combined = result.stdout.isEmpty ? state.output : result.stdout
        
        // Parse token JSON
        guard let tokenRange = combined.range(of: #"\{[\s\S]*"access_token"[\s\S]*\}"#, options: .regularExpression) else {
            throw RcloneError.configurationFailed("Did not receive valid Google Drive token. Please try again.")
        }
        
        let tokenJson = String(combined[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create remote in rclone config with the OAuth token
        let createResult = try await runner.run(rclonePath, arguments: configArgs + [
            "config", "create", name, "drive",
            "scope", "drive",
            "token", tokenJson
        ])
        
        guard createResult.isSuccess else {
            throw RcloneError.configurationFailed("Failed to save remote config: \(createResult.stderr)")
        }
    }
    
    /// Rename an existing remote
    func renameRemote(from oldName: String, to newName: String) async throws {
        let showResult = try await runner.run(rclonePath, arguments: configArgs + ["config", "show", oldName])
        guard showResult.isSuccess else {
            throw RcloneError.invalidRemote(oldName)
        }
        
        let configLines = showResult.stdout.components(separatedBy: "\n")
        var token = ""
        for line in configLines {
            if line.hasPrefix("token = ") {
                token = String(line.dropFirst("token = ".count))
            }
        }
        
        let createArgs = ["config", "create", newName, "drive", "token", token]
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

        if mode == .initial {
            args.append(contentsOf: ["--resync-mode", "newer"])
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
            if result.exitCode == 7 {
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
