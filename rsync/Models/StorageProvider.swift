//
//  StorageProvider.swift
//  rsync
//

import Foundation

enum ProviderAuthType: String, CaseIterable, Codable {
    case oauth
    case mega
    case webdav
    case s3
    case b2
    case sftp
    case protondrive
    case custom
}

struct StorageProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let authType: ProviderAuthType
    let subtitle: String
    
    static let supportedProviders: [StorageProvider] = [
        StorageProvider(
            id: "drive",
            name: "Google Drive",
            icon: "externaldrive.badge.icloud",
            authType: .oauth,
            subtitle: "OAuth 2.0 Web Authentication"
        ),
        StorageProvider(
            id: "mega",
            name: "MEGA",
            icon: "m.circle.fill",
            authType: .mega,
            subtitle: "User Email & Password"
        ),
        StorageProvider(
            id: "onedrive",
            name: "Microsoft OneDrive",
            icon: "cloud.fill",
            authType: .oauth,
            subtitle: "Personal or Work/School Account"
        ),
        StorageProvider(
            id: "dropbox",
            name: "Dropbox",
            icon: "shippingbox.fill",
            authType: .oauth,
            subtitle: "Personal or Team Dropbox"
        ),
        StorageProvider(
            id: "box",
            name: "Box",
            icon: "archivebox.fill",
            authType: .oauth,
            subtitle: "Box.com Cloud Storage"
        ),
        StorageProvider(
            id: "pcloud",
            name: "pCloud",
            icon: "p.circle.fill",
            authType: .oauth,
            subtitle: "pCloud Cloud Storage"
        ),
        StorageProvider(
            id: "webdav",
            name: "Nextcloud / WebDAV",
            icon: "network",
            authType: .webdav,
            subtitle: "Nextcloud, ownCloud, or custom WebDAV"
        ),
        StorageProvider(
            id: "s3",
            name: "Amazon S3 / Cloudflare R2",
            icon: "server.rack",
            authType: .s3,
            subtitle: "S3, Cloudflare R2, MinIO, Wasabi"
        ),
        StorageProvider(
            id: "b2",
            name: "Backblaze B2",
            icon: "cylinder.split.1x2.fill",
            authType: .b2,
            subtitle: "Backblaze B2 Cloud Storage"
        ),
        StorageProvider(
            id: "sftp",
            name: "SFTP / SSH",
            icon: "terminal.fill",
            authType: .sftp,
            subtitle: "SSH File Transfer Protocol"
        ),
        StorageProvider(
            id: "protondrive",
            name: "Proton Drive",
            icon: "lock.shield.fill",
            authType: .protondrive,
            subtitle: "Proton Drive Encrypted Storage"
        ),
        StorageProvider(
            id: "custom",
            name: "Other Rclone Provider",
            icon: "slider.horizontal.3",
            authType: .custom,
            subtitle: "Any of rclone's 40+ backends or Terminal setup"
        )
    ]
}
