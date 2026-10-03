// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ElevenSpeak",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ElevenSpeak", targets: ["ElevenSpeak"])
    ],
    targets: [
        .executableTarget(name: "ElevenSpeak", path: "Sources/ElevenSpeak")
    ]
)
