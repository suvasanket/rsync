//
//  SettingsView.swift
//  GoogleDriveSync
//
//  Created by saihgupr on 2024-12-11.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @LocalState private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SyncSettingsView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(0)
            
            AccountsSettingsView()
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }
                .tag(1)
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(2)
        }
        .frame(width: 500, height: 450)
        .padding(.bottom, 20)
    }
}

// MARK: - Sync Settings Tab

struct SyncSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @LocalState private var showingAddSheet = false
    @LocalState private var showingAddAccountSheet = false
    @LocalState private var selectedFolder: SyncFolder?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sync Folders")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(syncManager.availableRemotes.isEmpty)
                .help("Add a new sync folder")
            }
            
            if syncManager.folders.isEmpty {
                if syncManager.availableRemotes.isEmpty {
                    // No accounts at all
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue.gradient)
                        
                        Text("Welcome to rsync")
                            .font(.title2.bold())
                        
                        Text("Configure a cloud storage provider to start syncing folders.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            showingAddAccountSheet = true
                        } label: {
                            Label("Connect Account", systemImage: "link")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Text("This will open a terminal window to configure rclone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Has accounts, no folders
                    ContentUnavailableView {
                        Label("No Folders", systemImage: "folder")
                    } description: {
                        Text("Add a folder to start syncing")
                    } actions: {
                        Button("Add Folder") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxHeight: .infinity)
                }
            } else {
                List(syncManager.folders) { folder in
                    FolderSettingsRow(folder: folder, onEdit: {
                        selectedFolder = folder
                    })
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            AddFolderSheet()
                .environmentObject(syncManager)
        }
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheet()
                .environmentObject(syncManager)
        }
        .sheet(item: $selectedFolder) { folder in
            EditFolderSheet(folder: folder)
                .environmentObject(syncManager)
        }
    }
}

struct FolderSettingsRow: View {
    let folder: SyncFolder
    let onEdit: () -> Void
    @EnvironmentObject var syncManager: SyncManager
    
    @LocalState private var showingErrorPopover = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Status Icon
            Button {
                if folder.lastSyncStatus == .error {
                    showingErrorPopover = true
                }
            } label: {
                Group {
                    switch folder.lastSyncStatus {
                    case .idle:
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.tertiary)
                    case .syncing:
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.system(size: 16))
                .frame(width: 20)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingErrorPopover) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Failed")
                        .font(.headline)
                        .foregroundStyle(.red)
                    
                    if let error = folder.lastError {
                        ScrollView {
                            Text(error)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    } else {
                        Text("Unknown error occurred.")
                            .font(.caption)
                    }
                }
                .padding()
                .frame(width: 300)
            }

            // Folder info (takes available space)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(folder.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(folder.syncMode == .bisync ? "Two-way" : "One-way")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(folder.localPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(folder.fullRemotePath.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer(minLength: 8)
            
            // Controls (fixed width)
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { folder.isEnabled },
                    set: { newValue in
                        var updated = folder
                        updated.isEnabled = newValue
                        syncManager.updateFolder(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    syncManager.removeFolder(folder)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Add Folder Sheet

struct AddFolderSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    
    @LocalState private var localPath: String = ""
    @LocalState private var selectedRemote: RcloneRemote?
    @LocalState private var remotePath: String = ""
    @LocalState private var ignoredPatternsText: String = ""
    @LocalState private var syncMode: SyncMode = .sync
    @LocalState private var syncOnFirstConnection: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Sync Folder")
                .font(.headline)
            
            Form {
                Section {
                    HStack {
                        TextField("Local Folder", text: $localPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse...") {
                            selectFolder()
                        }
                    }
                }
                
                Section {
                    Picker("Remote Account", selection: $selectedRemote) {
                        Text("Select...").tag(nil as RcloneRemote?)
                        ForEach(syncManager.availableRemotes) { remote in
                            Text(remote.displayName).tag(remote as RcloneRemote?)
                        }
                    }
                    
                    TextField("Destination Folder (optional)", text: $remotePath)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Leave empty to sync to the root.\nOr type a folder path (e.g. 'Backups/MyMac').")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    Toggle(
                        "Two-way sync",
                        isOn: Binding(
                            get: {
                                syncMode == .bisync
                            },
                            set: { enabled in
                                syncMode = enabled ? .bisync : .sync
                            }
                        )
                    )

                    Text(
                        syncMode == .bisync
                        ? "Changes on both the local and remote side are synchronized."
                        : "The remote folder is mirrored from the local folder."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if syncMode == .bisync {
                        Toggle("Sync on first connection", isOn: $syncOnFirstConnection)
                        Text("Automatically trigger initial sync once online connectivity is established.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                } header: {
                    Text("Sync Mode")
                }

                Section {
                    TextEditor(text: $ignoredPatternsText)
                        .frame(height: 80)
                        .font(.system(.body, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    Text("Enter patterns to ignore (one per line). e.g., 'node_modules/**' or '.git/**'")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Ignored Files/Folders")
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add") {
                    if let remote = selectedRemote {
                        let parsedPatterns = ignoredPatternsText
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                            
                        let folder = SyncFolder(
                            localPath: localPath,
                            remoteName: remote.name,
                            remotePath: remotePath,
                            ignoredPatterns: parsedPatterns,
                            syncMode: syncMode,
                            syncOnFirstConnection: syncOnFirstConnection
                        )
                        syncManager.folders.append(folder)
                        syncManager.saveFolders()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(localPath.isEmpty || selectedRemote == nil)
            }
        }
        .padding()
        .frame(width: 450, height: 450)
        .onAppear {
            if localPath.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    selectFolder()
                }
            }
        }
    }
    
    private func selectFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Select a local folder to sync with Google Drive"
        panel.level = .floating
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                localPath = url.path
            }
        }
    }
}

// MARK: - Edit Folder Sheet

struct EditFolderSheet: View {
    let folder: SyncFolder
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    
    @LocalState private var localPath: String = ""
    @LocalState private var selectedRemote: RcloneRemote?
    @LocalState private var remotePath: String = ""
    @LocalState private var ignoredPatternsText: String = ""
    @LocalState private var syncMode: SyncMode = .sync
    @LocalState private var syncOnFirstConnection: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Sync Folder")
                .font(.headline)
            
            Form {
                Section {
                    HStack {
                        TextField("Local Folder", text: $localPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse...") {
                            selectFolder()
                        }
                    }
                }
                
                Section {
                    Picker("Remote Account", selection: $selectedRemote) {
                        Text("Select...").tag(nil as RcloneRemote?)
                        ForEach(syncManager.availableRemotes) { remote in
                            Text(remote.displayName).tag(remote as RcloneRemote?)
                        }
                    }
                    
                    TextField("Remote Path", text: $remotePath)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    Toggle(
                        "Two-way sync",
                        isOn: Binding(
                            get: {
                                syncMode == .bisync
                            },
                            set: { enabled in
                                syncMode = enabled ? .bisync : .sync
                            }
                        )
                    )

                    Text(
                        syncMode == .bisync
                        ? "Changes on both the local and remote side are synchronized."
                        : "The remote folder is mirrored from the local folder."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if syncMode == .bisync {
                        Toggle("Sync on first connection", isOn: $syncOnFirstConnection)
                        Text("Automatically trigger initial sync once online connectivity is established.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                } header: {
                    Text("Sync Mode")
                }
                
                Section {
                    TextEditor(text: $ignoredPatternsText)
                        .frame(height: 80)
                        .font(.system(.body, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    Text("Enter patterns to ignore (one per line). e.g., 'node_modules/**' or '.git/**'")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Ignored Files/Folders")
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    if let remote = selectedRemote {
                        var updated = folder
                        updated.localPath = localPath
                        updated.remoteName = remote.name
                        updated.remotePath = remotePath
                        updated.syncMode = syncMode
                        updated.syncOnFirstConnection = syncOnFirstConnection
                        
                        updated.ignoredPatterns = ignoredPatternsText
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                            
                        syncManager.updateFolder(updated)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(localPath.isEmpty || selectedRemote == nil)
            }
        }
        .padding()
        .frame(width: 450, height: 450)
        .onAppear {
            localPath = folder.localPath
            remotePath = folder.remotePath
            selectedRemote = syncManager.availableRemotes.first { $0.name == folder.remoteName }
            ignoredPatternsText = folder.ignoredPatterns.joined(separator: "\n")
            syncMode = folder.syncMode
            syncOnFirstConnection = folder.syncOnFirstConnection
        }
    }
    
    private func selectFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Select a local folder to sync with Google Drive"
        panel.level = .floating
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                localPath = url.path
            }
        }
    }
}

// MARK: - Add Account Sheet

struct AddAccountSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    
    @LocalState private var accountName: String = ""
    @LocalState private var isAuthenticating: Bool = false
    @LocalState private var authError: String? = nil
    
    var body: some View {
        VStack(spacing: 25) {
            Image(systemName: "safari.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue.gradient)
            
            VStack(spacing: 12) {
                Text("Connect Google Drive")
                    .font(.title3.bold())
                
                Text("Give your account a name. This will open your web browser to sign in to Google Drive.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Account Name (e.g. Work Drive)", text: $accountName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isAuthenticating)
                
                if let error = authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isAuthenticating)
                
                Button {
                    authenticate()
                } label: {
                    if isAuthenticating {
                        HStack {
                            Text("Authenticating...")
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Text("Connect Account")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sanitizedName.isEmpty || isAuthenticating)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    private var sanitizedName: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_@.-"))
        return String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            .replacingOccurrences(of: " ", with: "_")
    }
    
    private func authenticate() {
        guard !sanitizedName.isEmpty else { return }
        
        // Check if name already exists
        if syncManager.availableRemotes.contains(where: { $0.name == sanitizedName }) {
            authError = "An account with this name already exists."
            return
        }
        
        isAuthenticating = true
        authError = nil
        
        Task {
            do {
                try await syncManager.addNewDriveRemote(name: sanitizedName)
                dismiss()
            } catch {
                authError = error.localizedDescription
                isAuthenticating = false
            }
        }
    }
}

// MARK: - Accounts Tab

struct AccountsSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @LocalState private var showingAddAccountSheet = false
    @LocalState private var showingRenameSheet = false
    @LocalState private var accountToRename: RcloneRemote?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected Accounts")
                .font(.headline)
            
            if syncManager.availableRemotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)
                    
                    Text("No accounts connected")
                        .font(.title3)
                    
                    Button {
                        showingAddAccountSheet = true
                    } label: {
                        Label("Connect Account", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(syncManager.availableRemotes) { remote in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading) {
                            Text(remote.name)
                                .font(.body)
                            Text(remote.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            accountToRename = remote
                            showingRenameSheet = true
                        } label: {
                            Label("Rename...", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            Task {
                                await syncManager.deleteRemote(name: remote.name)
                            }
                        } label: {
                            Label("Remove Account", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.inset)
                
                Divider()
                
                HStack {
                    Button {
                        showingAddAccountSheet = true
                    } label: {
                        Label("Add Another Account", systemImage: "plus")
                    }
                    
                    Spacer()
                    
                    Button("Refresh") {
                        Task {
                            await syncManager.refreshRemotes()
                        }
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheet()
                .environmentObject(syncManager)
        }
        .sheet(isPresented: $showingRenameSheet) {
            if let remote = accountToRename {
                RenameAccountSheet(currentName: remote.name)
                    .environmentObject(syncManager)
            }
        }
        .onAppear {
            Task {
                await syncManager.refreshRemotes()
            }
        }
    }
}

// MARK: - Rename Account Sheet

struct RenameAccountSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    
    let currentName: String
    @LocalState private var newName: String = ""
    @LocalState private var isProcessing = false
    @LocalState private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Account")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Current name: \(currentName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("New name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button {
                    renameAccount()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal)
                    } else {
                        Text("Rename")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sanitizedName.isEmpty || sanitizedName == currentName || isProcessing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 350)
        .onAppear {
            newName = currentName
        }
    }
    
    private func renameAccount() {
        isProcessing = true
        errorMessage = nil
        
        Task {
            let success = await syncManager.renameRemote(from: currentName, to: sanitizedName)
            
            if success {
                dismiss()
            } else {
                errorMessage = "Failed to rename account"
                isProcessing = false
            }
        }
    }
    
    private var sanitizedName: String {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_@.-"))
        return String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @LocalState private var showingResetConfirmation = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Watch for changes (Real-Time Sync)", isOn: $syncManager.settings.watchForChanges)
                
                if syncManager.settings.watchForChanges {
                    HStack {
                        Text("Quiet Period (Debounce)")
                        Spacer()
                        Text("\(String(format: "%.1f", syncManager.settings.debounceDelaySeconds))s")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("File System Watching")
            } footer: {
                Text("Automatically detects created, modified, or deleted files and triggers a sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Picker("Sync Interval", selection: $syncManager.settings.syncInterval) {
                    ForEach(SyncInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                
                if case .daily = syncManager.settings.syncInterval {
                    DatePicker(
                        "Sync Time",
                        selection: $syncManager.settings.dailySyncTime,
                        displayedComponents: .hourAndMinute
                    )
                }
                
                Toggle("Sync when app launches", isOn: $syncManager.settings.syncOnLaunch)
                Toggle("Sync on first connection (Bi-Sync)", isOn: $syncManager.settings.syncOnFirstConnection)
            } header: {
                Text("Optional Sync Schedule & Connectivity")
            } footer: {
                Text("When 'Sync on first connection' is enabled, bi-sync folders automatically perform an initial sync when internet connectivity is detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ConfigStore.shared.configDirectoryURL.path)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Stores config.json (folders & preferences) and rclone.conf (accounts & credentials).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Button("Change Config Folder...") {
                            promptChangeConfigDirectory()
                        }
                        
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.open(ConfigStore.shared.configDirectoryURL)
                        }
                        
                        let defaultHomePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".rsync").path
                        if ConfigStore.shared.configDirectoryURL.path != defaultHomePath {
                            Button("Reset to Default") {
                                Task { @MainActor in
                                    await syncManager.resetConfigDirectory()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Configuration Storage (Hidden Folder)")
            } footer: {
                Text("All sync accounts, folder mappings, and preferences persist in this hidden directory across app runs. You can also override the path with the RSYNC_CONFIG_DIR environment variable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Toggle("Show notifications after sync", isOn: $syncManager.settings.showNotifications)
                Toggle("Notify on Error", isOn: $syncManager.settings.notifyOnError)
                Toggle("Launch at login", isOn: $syncManager.settings.launchAtLogin)
            } header: {
                Text("App Behavior")
            }
            
            Section {
                Button("Reset Everything...", role: .destructive) {
                    showingResetConfirmation = true
                }
            } header: {
                Text("Danger Zone")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: syncManager.settings) { _, _ in
            syncManager.saveSettings()
        }
        .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Everything", role: .destructive) {
                syncManager.resetAllSettings()
            }
        } message: {
            Text("This will remove all sync folders and account connections from the app. This cannot be undone.")
        }
    }
    
    private func promptChangeConfigDirectory() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Select a folder to store rsync configurations"
        panel.level = .floating
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                Task { @MainActor in
                    await syncManager.changeConfigDirectory(to: selectedURL)
                }
            }
        }
    }
}
