// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "GameCapture", platforms: [.macOS(.v14)], products: [.executable(name: "GameCapture", targets: ["GameCapture"])], targets: [.executableTarget(name: "GameCapture", resources: [.process("Resources")]), .testTarget(name: "GameCaptureTests", dependencies: ["GameCapture"])])
