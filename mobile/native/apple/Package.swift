// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CrispyCompanionCore",
  platforms: [.iOS(.v16), .watchOS(.v9), .macOS(.v13)],
  products: [.library(name: "CrispyCompanionCore", targets: ["CrispyCompanionCore"])],
  targets: [.target(name: "CrispyCompanionCore"),
    .testTarget(name: "CrispyCompanionCoreTests", dependencies: ["CrispyCompanionCore"])])
