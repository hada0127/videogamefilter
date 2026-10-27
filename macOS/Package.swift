// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "GameCapture", platforms: [.macOS(.v14)], products: [.executable(name: "GameCapture", targets: ["GameCapture"])], targets: [.target(name: "AgentControlProtocol"), .executableTarget(name: "GameCapture", dependencies: ["AgentControlProtocol"], resources: [.process("Resources")]), .testTarget(name: "GameCaptureTests", dependencies: ["GameCapture", "AgentControlProtocol"])])
