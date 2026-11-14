// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Chronicle",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Chronicle", targets: ["Chronicle"])
    ],
    targets: [
        .target(
            name: "ChronicleCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Chronicle",
            dependencies: ["ChronicleCore"]
        )
    ]
)
