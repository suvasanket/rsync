//
//  SyncManager.swift
//  rsync
//
//  Created by saihgupr on 2024-12-11.
//  Updated with dotfile persistence, network monitor, and bi-sync on first connection on 2026-09-25.
//

import Foundation
import SwiftUI
import UserNotifications
import ServiceManagement

@MainActor
class SyncManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var folders: [SyncFolder] = []
    @Published var settings: AppSettings
    @Published var isRcloneInstalled: Bool = false
    @Published var rcloneVersion: String = ""
    @Published var availableRemotes: [RcloneRemote] = []
    @Published var isSyncing: Bool = false
    @Published var currentSyncFolder: SyncFolder?
    @Published var lastSyncDate: Date?
    @Published var syncProgress: String = ""
    @Published var syncProgressPercent: Double? = nil  // 0.0 to 1.0
    @Published private(set) var syncCancelled: Bool = false
    @Published var isWatching: Bool = false
    @Published var isOnline: Bool = true
    
    // MARK: - Computed Properties
    
    var enabledFolders: [SyncFolder] {
        folders.filter { $0.isEnabled }
    }
    
    var statusIcon: String {
        if !isRcloneInstalled {
            return "exclamationmark.icloud"
        } else if !isOnline {
            return "icloud.slash"
        } else if isSyncing {
            return "arrow.triangle.2.circlepath.icloud"
        } else if enabledFolders.contains(where: { $0.lastSyncStatus == .error }) {
            return "xmark.icloud"
        } else if settings.watchForChanges && !enabledFolders.isEmpty {
            return "bolt.horizontal.icloud"
        } else {
            return "checkmark.icloud"
        }
    }
    
    var statusText: String {
        if !isRcloneInstalled {
            return "rclone not installed"
        } else if !isOnline {
            return "Offline (Sync paused)"
        } else if isSyncing {
            if let folder = currentSyncFolder {
                return "Syncing \(folder.displayName)..."
            }
            return "Syncing..."
        } else {
            let errorCount = enabledFolders.filter { $0.lastSyncStatus == .error }.count
            if errorCount > 0 {
                return "\(errorCount) folder\(errorCount == 1 ? "" : "s") failed to sync"
            } else if settings.watchForChanges && !enabledFolders.isEmpty {
                if let lastSync = lastSyncDate {
                    let formatter = RelativeDateTimeFormatter()
                    formatter.unitsStyle = .abbreviated
                    return "Watching • Last sync: \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
                }
                return "Watching for changes"
            } else if let lastSync = lastSyncDate {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                return "Last sync: \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
            } else {
                return "Ready"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var rclone: RcloneWrapper!
    private var syncTimer: Timer?
    private var watchers: [UUID: FolderWatcher] = [:]
    private var pendingSyncFolderIDs = Set<UUID>()
    private let configStore = ConfigStore.shared
    private let networkMonitor = NetworkMonitor.shared
    
    // MARK: - Initialization
    
    init() {
        let (loadedSettings, loadedFolders) = configStore.load()
        self.settings = loadedSettings
        self.folders = loadedFolders
        self.isOnline = networkMonitor.isConnected
        
        // Auto-detect rclone if current path doesn't exist
        if !FileManager.default.fileExists(atPath: self.settings.rclonePath),
           let detected = AppSettings.detectRclonePath() {
            self.settings.rclonePath = detected
        }
        
        self.rclone = RcloneWrapper(rclonePath: self.settings.rclonePath)
        
        setupNetworkObserver()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("SyncManager: Application will terminate. Flushing configurations to dotfile...")
                self?.saveFolders()
                self?.saveSettings()
            }
        }
        
        Task {
            await checkRcloneInstallation()
            await refreshRemotes()
            scheduleSync()
            refreshWatchers()
            
            if settings.syncOnLaunch && !folders.isEmpty && isOnline {
                await syncAll()
            }
        }
    }
    
    // MARK: - Network Observer
    
    private func setupNetworkObserver() {
        networkMonitor.onConnectivityChange = { [weak self] online, isFirstOnline in
            Task { @MainActor in
                guard let self = self else { return }
                self.isOnline = online
                
                if online {
                    print("SyncManager: Network online.")
                    if isFirstOnline && self.settings.syncOnFirstConnection {
                        await self.performFirstConnectionSync()
                    }
                    self.processNextPendingSync()
                } else {
                    print("SyncManager: Network offline. Pausing active syncs.")
                    if self.isSyncing {
                        self.cancelSync()
                    }
                }
            }
        }
    }
    
    private func performFirstConnectionSync() async {
        print("SyncManager: Running initial sync on first connection for bi-sync folders...")
        let targets = folders.filter { $0.isEnabled && $0.syncMode == .bisync && $0.syncOnFirstConnection }
        for folder in targets {
            guard !syncCancelled && isOnline else { break }
            await syncFolder(folder)
        }
    }
    
    // MARK: - Persistence (Dotfile ~/.rsync/config.json)
    
    func saveFolders() {
        configStore.save(settings: settings, folders: folders)
        refreshWatchers()
    }
    
    func saveSettings() {
        configStore.save(settings: settings, folders: folders)
        rclone = RcloneWrapper(rclonePath: settings.rclonePath)
        updateLaunchAtLogin()
        scheduleSync()
        refreshWatchers()
    }
    
    /// Change the configuration directory to a user-chosen path
    func changeConfigDirectory(to newURL: URL) async {
        do {
            try configStore.changeConfigDirectory(to: newURL)
            let (newSettings, newFolders) = configStore.load()
            self.settings = newSettings
            self.folders = newFolders
            self.rclone = RcloneWrapper(rclonePath: self.settings.rclonePath)
            await refreshRemotes()
            refreshWatchers()
            saveSettings()
            saveFolders()
        } catch {
            print("SyncManager: Error changing config directory: \(error)")
        }
    }
    
    /// Reset the configuration directory back to ~/.rsync
    func resetConfigDirectory() async {
        do {
            try configStore.resetToDefaultDirectory()
            let (newSettings, newFolders) = configStore.load()
            self.settings = newSettings
            self.folders = newFolders
            self.rclone = RcloneWrapper(rclonePath: self.settings.rclonePath)
            await refreshRemotes()
            refreshWatchers()
            saveSettings()
            saveFolders()
        } catch {
            print("SyncManager: Error resetting config directory: \(error)")
        }
    }
    
    // MARK: - File Watcher Management (Native FSEvents)
    
    func refreshWatchers() {
        guard settings.watchForChanges else {
            stopAllWatchers()
            isWatching = false
            return
        }
        
        let enabledIDs = Set(folders.filter { $0.isEnabled }.map { $0.id })
        
        for (id, watcher) in watchers where !enabledIDs.contains(id) {
            watcher.stop()
            watchers.removeValue(forKey: id)
        }
        
        for folder in folders where folder.isEnabled {
            let resolved = resolveLocalPath(folder.localPath)
            guard FileManager.default.fileExists(atPath: resolved) else { continue }
            
            if let existing = watchers[folder.id], existing.path == resolved {
                continue
            }
            
            watchers[folder.id]?.stop()
            
            let watcher = FolderWatcher(
                folderId: folder.id,
                path: resolved,
                ignoredPatterns: folder.ignoredPatterns,
                debounceDelay: settings.debounceDelaySeconds
            ) { [weak self] in
                Task { @MainActor in
                    self?.handleWatchedFolderChange(folderId: folder.id)
                }
            }
            
            watchers[folder.id] = watcher
            watcher.start()
        }
        
        isWatching = !watchers.isEmpty
    }
    
    private func stopAllWatchers() {
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
        isWatching = false
    }
    
    private func handleWatchedFolderChange(folderId: UUID) {
        guard let folder = folders.first(where: { $0.id == folderId && $0.isEnabled }) else { return }
        
        guard isOnline else {
            print("SyncManager: Network offline. Queuing change for \(folder.displayName) without spawning processes.")
            pendingSyncFolderIDs.insert(folderId)
            return
        }
        
        if isSyncing {
            print("SyncManager: Folder \(folder.displayName) change queued (sync active)")
            pendingSyncFolderIDs.insert(folderId)
        } else {
            print("SyncManager: Change detected in \(folder.displayName). Triggering sync...")
            Task {
                await syncFolder(folder)
                processNextPendingSync()
            }
        }
    }
    
    private func processNextPendingSync() {
        guard isOnline, !isSyncing, let nextFolderId = pendingSyncFolderIDs.popFirst() else { return }
        guard let folder = folders.first(where: { $0.id == nextFolderId && $0.isEnabled }) else {
            processNextPendingSync()
            return
        }
        
        Task {
            print("SyncManager: Processing queued sync for \(folder.displayName)...")
            await syncFolder(folder)
            processNextPendingSync()
        }
    }
    
    // MARK: - rclone Management
    
    func checkRcloneInstallation() async {
        isRcloneInstalled = await rclone.isInstalled()
        if isRcloneInstalled {
            do {
                rcloneVersion = try await rclone.version()
            } catch {
                rcloneVersion = "Unknown"
            }
        }
    }
    
    func refreshRemotes() async {
        guard isRcloneInstalled else { return }
        do {
            availableRemotes = try await rclone.listRemotes()
        } catch {
            print("Failed to list remotes: \(error)")
        }
    }
    
    /// Adds a new Google Drive remote using in-app browser OAuth flow
    func addNewDriveRemote(name: String, clientId: String? = nil, clientSecret: String? = nil) async throws {
        try await rclone.createDriveAccount(name: name, clientId: clientId, clientSecret: clientSecret)
        await refreshRemotes()
    }
    
    /// Adds an OAuth-based remote (OneDrive, Dropbox, Box, pCloud, etc.)
    func addOAuthAccount(
        name: String,
        type: String,
        clientId: String? = nil,
        clientSecret: String? = nil,
        extraConfig: [String: String] = [:]
    ) async throws {
        try await rclone.createOAuthAccount(
            name: name,
            type: type,
            clientId: clientId,
            clientSecret: clientSecret,
            extraConfig: extraConfig
        )
        await refreshRemotes()
    }
    
    /// Adds a credential or key-based remote (MEGA, WebDAV, Nextcloud, S3, B2, SFTP, etc.)
    func addConfigAccount(
        name: String,
        type: String,
        options: [String: String]
    ) async throws {
        try await rclone.createConfigAccount(name: name, type: type, options: options)
        await refreshRemotes()
    }
    
    /// Launch the interactive terminal configuration wizard
    func openTerminalConfig() {
        rclone.openTerminalConfig()
    }
    
    /// Pings and verifies connectivity to a specific remote
    func pingRemote(name: String) async -> RemotePingResult {
        await rclone.pingRemote(name: name)
    }
    
    /// Force a baseline resync for a two-way sync folder
    func resyncFolder(_ folder: SyncFolder) async {
        guard isOnline else { return }
        guard !isSyncing else { return }
        
        let folderID = folder.id
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        
        folders[index].bisyncState = .needsResync
        folders[index].lastError = nil
        saveFolders()
        await syncFolder(folders[index])
    }
    
    /// Rename a remote
    func renameRemote(from oldName: String, to newName: String) async -> Bool {
        do {
            try await rclone.renameRemote(from: oldName, to: newName)
            await refreshRemotes()
            
            for index in folders.indices where folders[index].remoteName == oldName {
                folders[index].remoteName = newName
                folders[index].bisyncState = .uninitialized
            }
            saveFolders()
            return true
        } catch {
            print("Failed to rename remote: \(error)")
            return false
        }
    }
    
    /// Delete a remote
    func deleteRemote(name: String) async {
        do {
            try await rclone.deleteRemote(name: name)
            await refreshRemotes()
            folders.removeAll { $0.remoteName == name }
            saveFolders()
        } catch {
            print("Failed to delete remote: \(error)")
        }
    }
    
    /// Reset all app data and settings
    func resetAllSettings() {
        stopAllWatchers()
        folders.removeAll()
        availableRemotes.removeAll()
        pendingSyncFolderIDs.removeAll()
        
        let detectedPath = AppSettings.detectRclonePath() ?? AppSettings.defaultRclonePath
        self.settings = AppSettings(rclonePath: detectedPath)
        self.rclone = RcloneWrapper(rclonePath: self.settings.rclonePath)
        
        saveSettings()
        saveFolders()
        
        Task {
            await checkRcloneInstallation()
            await refreshRemotes()
        }
    }
    
    // MARK: - Folder Management
    
    func addFolder(
        localPath: String,
        remoteName: String,
        remotePath: String = "",
        syncMode: SyncMode = .sync,
        syncOnFirstConnection: Bool = true
    ) {
        let folder = SyncFolder(
            localPath: localPath,
            remoteName: remoteName,
            remotePath: remotePath,
            syncMode: syncMode,
            syncOnFirstConnection: syncOnFirstConnection
        )
        folders.append(folder)
        saveFolders()
    }
    
    func removeFolder(_ folder: SyncFolder) {
        watchers[folder.id]?.stop()
        watchers.removeValue(forKey: folder.id)
        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }
    
    func updateFolder(_ folder: SyncFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }

        let oldFolder = folders[index]
        var updatedFolder = folder

        let syncConfigurationChanged =
            oldFolder.localPath != folder.localPath ||
            oldFolder.remoteName != folder.remoteName ||
            oldFolder.remotePath != folder.remotePath ||
            oldFolder.ignoredPatterns != folder.ignoredPatterns ||
            oldFolder.syncMode != folder.syncMode

        if syncConfigurationChanged {
            updatedFolder.bisyncState = .uninitialized
        }

        folders[index] = updatedFolder
        saveFolders()
    }
    
    // MARK: - Sync Operations
    
    func syncAll() async {
        guard isOnline else {
            print("SyncManager: Network offline, skipping syncAll.")
            return
        }
        guard !isSyncing else { return }
        syncCancelled = false
        isSyncing = true

        let folderIDs = folders.filter { $0.isEnabled }.map { $0.id }

        for folderID in folderIDs {
            guard !syncCancelled && isOnline else { break }

            guard let index = folders.firstIndex(where: { $0.id == folderID }) else { continue }

            currentSyncFolder = folders[index]
            folders[index].lastSyncStatus = .syncing
            
            let localPath = folders[index].localPath
            let remotePath = folders[index].fullRemotePath
            let ignoredPatterns = folders[index].ignoredPatterns
            let syncMode = folders[index].syncMode
            let bisyncState = folders[index].bisyncState
            let resolvedPath = resolveLocalPath(localPath)

            do {
                await rclone.ensureRemoteDirectoryExists(remotePath)
                let result: SyncResult

                switch syncMode {
                case .sync:
                    result = try await rclone.sync(
                        source: resolvedPath,
                        destination: remotePath,
                        ignoredPatterns: ignoredPatterns
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.syncProgress = self?.simplifyProgress(progress) ?? progress
                            self?.syncProgressPercent = self?.parseProgressPercent(from: progress)
                        }
                    }

                case .bisync:
                    let mode: BisyncMode
                    switch bisyncState {
                    case .uninitialized: mode = .initial
                    case .ready: mode = .normal
                    case .needsResync: mode = .resync
                    }

                    result = try await rclone.bidirectionalSync(
                        local: resolvedPath,
                        remote: remotePath,
                        ignoredPatterns: ignoredPatterns,
                        mode: mode
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.syncProgress = self?.simplifyProgress(progress) ?? progress
                            self?.syncProgressPercent = self?.parseProgressPercent(from: progress)
                        }
                    }
                }

                guard let currentIndex = folders.firstIndex(where: { $0.id == folderID }) else { continue }

                if result.success && syncMode == .bisync {
                    folders[currentIndex].bisyncState = .ready
                }

                folders[currentIndex].lastSyncDate = Date()
                folders[currentIndex].lastSyncStatus = result.success ? .success : .error
                folders[currentIndex].lastError = nil

            } catch {
                guard let currentIndex = folders.firstIndex(where: { $0.id == folderID }) else { continue }

                if syncCancelled {
                    folders[currentIndex].lastSyncStatus = .idle
                    folders[currentIndex].lastError = nil
                } else {
                    if syncMode == .bisync,
                       let rcloneError = error as? RcloneError,
                       case .bisyncNeedsResync(_) = rcloneError {
                        folders[currentIndex].bisyncState = .needsResync
                    }

                    folders[currentIndex].lastSyncStatus = .error
                    folders[currentIndex].lastError = error.localizedDescription
                }
            }
        }

        let wasCancelled = syncCancelled
        currentSyncFolder = nil
        syncProgress = ""
        syncProgressPercent = nil
        syncCancelled = false
        isSyncing = false

        if !wasCancelled {
            lastSyncDate = Date()
        }

        saveFolders()

        if !wasCancelled {
            await sendSyncNotification(folders)
        }
        
        processNextPendingSync()
    }

    /// Cancel the current sync operation
    func cancelSync() {
        guard isSyncing else { return }
        syncCancelled = true
        syncProgress = "Cancelling..."
        
        Task {
            await rclone.cancelCurrentOperation()
        }
    }
    
    func syncFolder(_ folder: SyncFolder) async {
        guard isOnline else {
            print("SyncManager: Network offline, skipping syncFolder.")
            return
        }
        guard !isSyncing else { return }

        let folderID = folder.id
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        
        syncCancelled = false
        isSyncing = true
        currentSyncFolder = folders[index]
        folders[index].lastSyncStatus = .syncing
        
        let localPath = folders[index].localPath
        let remotePath = folders[index].fullRemotePath
        let ignoredPatterns = folders[index].ignoredPatterns
        let syncMode = folders[index].syncMode
        let bisyncState = folders[index].bisyncState
        let resolvedPath = resolveLocalPath(localPath)
        
        do {
            await rclone.ensureRemoteDirectoryExists(remotePath)
            let result: SyncResult

            switch syncMode {
            case .sync:
                result = try await rclone.sync(
                    source: resolvedPath,
                    destination: remotePath,
                    ignoredPatterns: ignoredPatterns
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.syncProgress = self?.simplifyProgress(progress) ?? progress
                        self?.syncProgressPercent = self?.parseProgressPercent(from: progress)
                    }
                }

            case .bisync:
                let mode: BisyncMode
                switch bisyncState {
                case .uninitialized: mode = .initial
                case .ready: mode = .normal
                case .needsResync: mode = .resync
                }

                result = try await rclone.bidirectionalSync(
                    local: resolvedPath,
                    remote: remotePath,
                    ignoredPatterns: ignoredPatterns,
                    mode: mode
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.syncProgress = self?.simplifyProgress(progress) ?? progress
                        self?.syncProgressPercent = self?.parseProgressPercent(from: progress)
                    }
                }
            }
            
            if let currentIndex = folders.firstIndex(where: { $0.id == folderID }) {
                if result.success && syncMode == .bisync {
                    folders[currentIndex].bisyncState = .ready
                }

                folders[currentIndex].lastSyncDate = Date()
                folders[currentIndex].lastSyncStatus = result.success ? .success : .error
                folders[currentIndex].lastError = nil
            }
            
        } catch {
            if let currentIndex = folders.firstIndex(where: { $0.id == folderID }) {
                if syncCancelled {
                    folders[currentIndex].lastSyncStatus = .idle
                    folders[currentIndex].lastError = nil
                } else {
                    if syncMode == .bisync,
                       let rcloneError = error as? RcloneError,
                       case .bisyncNeedsResync(_) = rcloneError {
                        folders[currentIndex].bisyncState = .needsResync
                    }

                    folders[currentIndex].lastSyncStatus = .error
                    folders[currentIndex].lastError = error.localizedDescription
                }
            }
        }
        
        let wasCancelled = syncCancelled
        currentSyncFolder = nil
        syncProgress = ""
        syncProgressPercent = nil
        syncCancelled = false
        isSyncing = false

        if !wasCancelled {
            lastSyncDate = Date()
        }

        saveFolders()
    }
    
    private func resolveLocalPath(_ path: String) -> String {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        guard path.hasPrefix("/Volumes/") else { return path }
        
        let components = path.components(separatedBy: "/")
        guard components.count >= 3 else { return path }
        
        let volumeName = components[2]
        let relativePath = components.dropFirst(3).joined(separator: "/")
        
        var baseVolumeName = volumeName
        if let range = baseVolumeName.range(of: "-[0-9]+$", options: .regularExpression) {
            baseVolumeName.removeSubrange(range)
        }
        
        do {
            let volumes = try FileManager.default.contentsOfDirectory(atPath: "/Volumes")
            for candidate in volumes {
                var candidateBaseName = candidate
                if let range = candidateBaseName.range(of: "-[0-9]+$", options: .regularExpression) {
                    candidateBaseName.removeSubrange(range)
                }
                
                if candidateBaseName == baseVolumeName {
                    let newVolumePath = "/Volumes/\(candidate)"
                    let fullNewPath = relativePath.isEmpty ? newVolumePath : "\(newVolumePath)/\(relativePath)"
                    if FileManager.default.fileExists(atPath: fullNewPath) {
                        return fullNewPath
                    }
                }
            }
        } catch {}
        
        return path
    }
    
    private func parseProgressPercent(from output: String) -> Double? {
        let pattern = #"(\d+)%"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output),
           let percent = Double(output[range]) {
            return percent / 100.0
        }
        return nil
    }
    
    private func simplifyProgress(_ progress: String) -> String {
        let bytesPattern = #"([\d.]+)\s*([\w]+)\s*/\s*([\d.]+)\s*([\w]+)"#
        if let regex = try? NSRegularExpression(pattern: bytesPattern),
           let match = regex.firstMatch(in: progress, range: NSRange(progress.startIndex..., in: progress)) {
            if let range1 = Range(match.range(at: 1), in: progress),
               let range3 = Range(match.range(at: 3), in: progress),
               let range4 = Range(match.range(at: 4), in: progress) {
                let t = Double(progress[range1]) ?? 0
                let tot = Double(progress[range3]) ?? 0
                let unit = String(progress[range4])
                
                var eta = ""
                let etaPattern = #"ETA\s+([\w\d]+)"#
                if let etaRegex = try? NSRegularExpression(pattern: etaPattern),
                   let etaMatch = etaRegex.firstMatch(in: progress, range: NSRange(progress.startIndex..., in: progress)),
                   let etaRange = Range(etaMatch.range(at: 1), in: progress) {
                    eta = String(progress[etaRange])
                }
                
                var result = String(format: "%.1f / %.1f %@", t, tot, unit)
                if !eta.isEmpty && eta != "-" {
                    result += " • ETA \(eta)"
                }
                return result
            }
        }
        return progress
    }
    
    // MARK: - Optional Scheduled Timer
    
    private func scheduleSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        
        if case .daily = settings.syncInterval {
            scheduleDailySync()
            return
        }
        
        guard let interval = settings.syncInterval.intervalSeconds else { return }
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll()
            }
        }
    }
    
    private func scheduleDailySync() {
        let calendar = Calendar.current
        let syncTimeComponents = calendar.dateComponents([.hour, .minute], from: settings.dailySyncTime)
        
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        todayComponents.hour = syncTimeComponents.hour
        todayComponents.minute = syncTimeComponents.minute
        todayComponents.second = 0
        
        let nextSyncDate: Date
        if let todayAtSyncTime = calendar.date(from: todayComponents) {
            if todayAtSyncTime > Date() {
                nextSyncDate = todayAtSyncTime
            } else {
                nextSyncDate = calendar.date(byAdding: .day, value: 1, to: todayAtSyncTime) ?? todayAtSyncTime
            }
        } else {
            nextSyncDate = Date().addingTimeInterval(24 * 60 * 60)
        }
        
        let timeUntilSync = nextSyncDate.timeIntervalSince(Date())
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: timeUntilSync, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll()
                self?.scheduleDailySync()
            }
        }
    }
    
    // MARK: - Notifications
    
    private func sendSyncNotification(_ folders: [SyncFolder]) async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let errorCount = folders.filter { $0.lastSyncStatus == .error }.count
        let hasErrors = errorCount > 0
        
        if !settings.showNotifications && !(hasErrors && settings.notifyOnError) {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        if hasErrors {
            content.title = "Sync Failed"
            content.body = "\(errorCount) folder(s) encountered errors"
            content.categoryIdentifier = "SYNC_ERROR"
        } else {
            guard settings.showNotifications else { return }
            content.title = "Sync Complete"
            content.body = "\(folders.count) folder(s) synced successfully"
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Launch at Login
    
    private func updateLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
