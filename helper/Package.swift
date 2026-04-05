// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "shanbay-cookie-helper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "shanbay-cookie-helper",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
