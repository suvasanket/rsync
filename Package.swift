// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "rsync",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "rsync", targets: ["rsync"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "rsync",
            path: "GoogleDriveSync",
            exclude: [
                "Info.plist",
                "GoogleDriveSync.entitlements",
                "Assets.xcassets"
            ]
        )
    ]
)
