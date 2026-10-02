// swift-tools-version: 5.9

import PackageDescription

// Independent target; inherited Fermín sources are retained only as provenance.
let package = Package(name: "AnimaStudio", platforms: [.macOS(.v13)], products: [.executable(name: "AnimaStudio", targets: ["AnimaStudio"])], targets: [.target(name: "NDIBridge", path: "NDIBridge"), .executableTarget(name: "AnimaStudio", dependencies: ["NDIBridge"], path: "Studio"), .testTarget(name: "StudioTests", dependencies: ["AnimaStudio"], path: "StudioTests")], swiftLanguageVersions: [.v5])
