//
//  SettingsView.swift
//  rsync
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
                
                if folder.syncMode == .bisync {
                    Button {
                        Task {
                            await syncManager.resyncFolder(folder)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(folder.bisyncState == .needsResync ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Resync folder baseline")
                }
                
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
        panel.message = "Select a local folder to sync"
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
        panel.message = "Select a local folder to sync"
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
    
    @LocalState private var selectedProvider: StorageProvider = StorageProvider.supportedProviders[0]
    @LocalState private var accountName: String = ""
    @LocalState private var isAuthenticating: Bool = false
    @LocalState private var authError: String? = nil
    
    // OAuth options
    @LocalState private var clientId: String = ""
    @LocalState private var clientSecret: String = ""
    @LocalState private var showCustomClientId: Bool = false
    
    // Credentials (MEGA, WebDAV, Proton, SFTP)
    @LocalState private var username: String = ""
    @LocalState private var password: String = ""
    @LocalState private var twoFactorCode: String = ""
    
    // WebDAV
    @LocalState private var webdavURL: String = ""
    @LocalState private var webdavVendor: String = "nextcloud"
    
    // S3
    @LocalState private var s3Provider: String = "Cloudflare"
    @LocalState private var s3Endpoint: String = ""
    @LocalState private var s3AccessKey: String = ""
    @LocalState private var s3SecretKey: String = ""
    @LocalState private var s3Region: String = ""
    
    // B2
    @LocalState private var b2AccountId: String = ""
    @LocalState private var b2ApplicationKey: String = ""
    
    // SFTP
    @LocalState private var sftpHost: String = ""
    @LocalState private var sftpPort: String = "22"
    @LocalState private var sftpKeyFile: String = ""
    
    // Custom
    @LocalState private var customType: String = ""
    @LocalState private var customOptions: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: selectedProvider.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect \(selectedProvider.name)")
                        .font(.headline)
                    Text(selectedProvider.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Picker("Storage Provider", selection: $selectedProvider) {
                ForEach(StorageProvider.supportedProviders) { provider in
                    Text(provider.name).tag(provider)
                }
            }
            .pickerStyle(.menu)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Name")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("e.g. My_\(selectedProvider.id)", text: $accountName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isAuthenticating)
                    }
                    
                    providerSpecificForm
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            
            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
            
            HStack(spacing: 12) {
                if selectedProvider.authType == .custom {
                    Button("Terminal Setup Wizard...") {
                        syncManager.openTerminalConfig()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                
                Spacer()
                
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
                            Text("Connecting...")
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Text(selectedProvider.authType == .oauth ? "Open Browser & Connect" : "Connect Account")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sanitizedName.isEmpty || isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
    
    @ViewBuilder
    private var providerSpecificForm: some View {
        switch selectedProvider.authType {
        case .oauth:
            VStack(alignment: .leading, spacing: 8) {
                Text("Clicking Connect will open your browser to log in securely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if selectedProvider.id == "drive" {
                    DisclosureGroup(
                        "Custom Google Client ID (Optional)",
                        isExpanded: $showCustomClientId
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Optional: Avoid Google's retiring shared client_id and rate limits.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            TextField("Client ID", text: $clientId)
                                .textFieldStyle(.roundedBorder)
                            
                            SecureField("Client Secret", text: $clientSecret)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
            
        case .mega:
            VStack(alignment: .leading, spacing: 8) {
                Text("MEGA Credentials")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("MEGA Email Address", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("MEGA Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                TextField("2FA Code (Optional)", text: $twoFactorCode)
                    .textFieldStyle(.roundedBorder)
                Text("Password is encrypted locally in ~/.rsync/rclone.conf.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
        case .webdav:
            VStack(alignment: .leading, spacing: 8) {
                Text("Server & Credentials")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Server URL (e.g. https://cloud.example.com/remote.php/dav/files/user/)", text: $webdavURL)
                    .textFieldStyle(.roundedBorder)
                Picker("Vendor", selection: $webdavVendor) {
                    Text("Nextcloud").tag("nextcloud")
                    Text("ownCloud").tag("owncloud")
                    Text("Fastmail").tag("fastmail")
                    Text("Other WebDAV").tag("other")
                }
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password or App Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .s3:
            VStack(alignment: .leading, spacing: 8) {
                Picker("S3 Provider", selection: $s3Provider) {
                    Text("Cloudflare R2").tag("Cloudflare")
                    Text("Amazon AWS S3").tag("AWS")
                    Text("Wasabi").tag("Wasabi")
                    Text("MinIO").tag("Minio")
                    Text("Other S3 Compatible").tag("Other")
                }
                TextField("Endpoint URL (optional for AWS)", text: $s3Endpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Access Key ID", text: $s3AccessKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret Access Key", text: $s3SecretKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Region (optional)", text: $s3Region)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .b2:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Account ID / Key ID", text: $b2AccountId)
                    .textFieldStyle(.roundedBorder)
                SecureField("Application Key", text: $b2ApplicationKey)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .sftp:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Host (e.g. sftp.example.com)", text: $sftpHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $sftpPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password (optional if using key)", text: $password)
                    .textFieldStyle(.roundedBorder)
                TextField("Private Key File Path (optional)", text: $sftpKeyFile)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .protondrive:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Proton Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Proton Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                TextField("2FA Code (Optional)", text: $twoFactorCode)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .custom:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Rclone Backend Type (e.g. koofr, zoho, yandex)", text: $customType)
                    .textFieldStyle(.roundedBorder)
                TextField("Parameters (key=value separated by spaces)", text: $customOptions)
                    .textFieldStyle(.roundedBorder)
                Text("Click 'Terminal Setup Wizard' below to configure using rclone's interactive CLI.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var sanitizedName: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_@.-"))
        return String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            .replacingOccurrences(of: " ", with: "_")
    }
    
    private func authenticate() {
        guard !sanitizedName.isEmpty else { return }
        
        if syncManager.availableRemotes.contains(where: { $0.name == sanitizedName }) {
            authError = "An account with this name already exists."
            return
        }
        
        isAuthenticating = true
        authError = nil
        
        Task {
            do {
                switch selectedProvider.authType {
                case .oauth:
                    var extra: [String: String] = [:]
                    if selectedProvider.id == "drive" {
                        extra["scope"] = "drive"
                    }
                    try await syncManager.addOAuthAccount(
                        name: sanitizedName,
                        type: selectedProvider.id,
                        clientId: clientId.isEmpty ? nil : clientId,
                        clientSecret: clientSecret.isEmpty ? nil : clientSecret,
                        extraConfig: extra
                    )
                    
                case .mega:
                    guard !username.isEmpty, !password.isEmpty else {
                        throw RcloneError.configurationFailed("Email and Password are required for MEGA.")
                    }
                    var opts: [String: String] = ["user": username, "pass": password]
                    if !twoFactorCode.isEmpty {
                        opts["2fa"] = twoFactorCode
                    }
                    try await syncManager.addConfigAccount(name: sanitizedName, type: "mega", options: opts)
                    
                case .webdav:
                    guard !webdavURL.isEmpty, !username.isEmpty, !password.isEmpty else {
                        throw RcloneError.configurationFailed("Server URL, Username, and Password are required.")
                    }
                    let opts = ["url": webdavURL, "vendor": webdavVendor, "user": username, "pass": password]
                    try await syncManager.addConfigAccount(name: sanitizedName, type: "webdav", options: opts)
                    
                case .s3:
                    guard !s3AccessKey.isEmpty, !s3SecretKey.isEmpty else {
                        throw RcloneError.configurationFailed("Access Key ID and Secret Access Key are required.")
                    }
                    var opts = ["provider": s3Provider, "access_key_id": s3AccessKey, "secret_access_key": s3SecretKey]
                    if !s3Endpoint.isEmpty { opts["endpoint"] = s3Endpoint }
                    if !s3Region.isEmpty { opts["region"] = s3Region }
                    try await syncManager.addConfigAccount(name: sanitizedName, type: "s3", options: opts)
                    
                case .b2:
                    guard !b2AccountId.isEmpty, !b2ApplicationKey.isEmpty else {
                        throw RcloneError.configurationFailed("Account ID and Application Key are required.")
                    }
                    let opts = ["account": b2AccountId, "key": b2ApplicationKey]
                    try await syncManager.addConfigAccount(name: sanitizedName, type: "b2", options: opts)
                    
                case .sftp:
                    guard !sftpHost.isEmpty, !username.isEmpty else {
                        throw RcloneError.configurationFailed("Host and Username are required.")
                    }
                    var opts = ["host": sftpHost, "port": sftpPort.isEmpty ? "22" : sftpPort, "user": username]
                    if !password.isEmpty { opts["pass"] = password }
                    if !sftpKeyFile.isEmpty { opts["key_file"] = sftpKeyFile }
                    try await syncManager.addConfigAccount(name: sanitizedName, type: "sftp", options: opts)
                    
                case .protondrive:
                    guard !username.isEmpty, !password.isEmpty else {
                        throw RcloneError.configurationFailed("Username and Password are required.")
                    }
                    var opts = ["username": username, "password": password]
                    if !twoFactorCode.isEmpty { opts["2fa"] = twoFactorCode }
                    try await syncManager.addConfigAccount(name: sanitizedName, type: "protondrive", options: opts)
                    
                case .custom:
                    let type = customType.trimmingCharacters(in: .whitespaces)
                    guard !type.isEmpty else {
                        throw RcloneError.configurationFailed("Rclone backend type is required.")
                    }
                    var opts: [String: String] = [:]
                    let pairs = customOptions.components(separatedBy: " ")
                    for pair in pairs {
                        let parts = pair.components(separatedBy: "=")
                        if parts.count == 2 {
                            opts[parts[0]] = parts[1]
                        }
                    }
                    try await syncManager.addConfigAccount(name: sanitizedName, type: type, options: opts)
                }
                
                // Verify link via ping check before closing sheet
                let ping = await syncManager.pingRemote(name: sanitizedName)
                if !ping.isSuccess {
                    authError = "Account created, but connection check failed:\n\(ping.message)"
                    isAuthenticating = false
                    return
                }
                
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
    @LocalState private var pingResults: [String: RemotePingResult] = [:]
    @LocalState private var pingingRemotes: Set<String> = []
    
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
                    
                    HStack(spacing: 12) {
                        Button {
                            showingAddAccountSheet = true
                        } label: {
                            Label("Connect Account", systemImage: "link")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button {
                            syncManager.openTerminalConfig()
                        } label: {
                            Label("Terminal Setup...", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(syncManager.availableRemotes) { remote in
                    HStack(spacing: 12) {
                        Image(systemName: remote.providerIcon)
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(remote.name)
                                .font(.body.weight(.medium))
                            Text(remote.type.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if pingingRemotes.contains(remote.name) {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Testing...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let ping = pingResults[remote.name] {
                            HStack(spacing: 4) {
                                Image(systemName: ping.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(ping.isSuccess ? .green : .red)
                                    .font(.caption)
                                Text(ping.message)
                                    .font(.caption)
                                    .foregroundStyle(ping.isSuccess ? .green : .red)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("Ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button {
                            Task {
                                pingingRemotes.insert(remote.name)
                                let res = await syncManager.pingRemote(name: remote.name)
                                pingResults[remote.name] = res
                                pingingRemotes.remove(remote.name)
                            }
                        } label: {
                            Label("Ping", systemImage: "network")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(pingingRemotes.contains(remote.name))
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
                        Label("Add Account", systemImage: "plus")
                    }
                    
                    Button {
                        Task {
                            for remote in syncManager.availableRemotes {
                                pingingRemotes.insert(remote.name)
                                let res = await syncManager.pingRemote(name: remote.name)
                                pingResults[remote.name] = res
                                pingingRemotes.remove(remote.name)
                            }
                        }
                    } label: {
                        Label("Ping All", systemImage: "network.badge.shield.half.filled")
                    }
                    .disabled(syncManager.availableRemotes.isEmpty)
                    
                    Button {
                        syncManager.openTerminalConfig()
                    } label: {
                        Label("Terminal Setup...", systemImage: "terminal")
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
    @ObservedObject private var launchAtLoginManager = LaunchAtLoginManager.shared
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
                
                if launchAtLoginManager.requiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Requires approval in macOS Login Items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            launchAtLoginManager.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("App Behavior")
            } footer: {
                if !launchAtLoginManager.statusDescription.isEmpty {
                    Text(launchAtLoginManager.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onAppear {
            launchAtLoginManager.refreshStatus()
        }
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
