// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "KeyboardCore", platforms: [.iOS(.v16), .macOS(.v10_15)], products: [.library(name: "KeyboardCore", targets: ["KeyboardCore"])], targets: [.target(name: "KeyboardCore", resources: [.process("Resources")]), .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"])])
