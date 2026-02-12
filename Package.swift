// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SugarNetwork",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SugarNetwork", targets: ["SugarNetwork"]),
        .library(name: "SugarNetworkMocks", targets: ["SugarNetworkMocks"])
    ],
    targets: [
        .target(name: "SugarNetwork"),
        .target(name: "SugarNetworkMocks", dependencies: ["SugarNetwork"]),
        .testTarget(name: "SugarNetworkTests", dependencies: ["SugarNetwork", "SugarNetworkMocks"])
    ]
)
