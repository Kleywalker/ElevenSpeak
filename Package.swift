// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"ElevenSpeak",platforms:[.macOS(.v13)],products:[.executable(name:"ElevenSpeak",targets:["ElevenSpeak"])],targets:[.executableTarget(name:"ElevenSpeak")])
