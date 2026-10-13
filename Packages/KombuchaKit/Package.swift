// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KombuchaKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KombuchaCore", targets: ["KombuchaCore"]),
        .library(name: "SMCKit", targets: ["SMCKit"]),
        .library(name: "HelperProtocol", targets: ["HelperProtocol"]),
        .library(name: "HelperCore", targets: ["HelperCore"]),
    ],
    targets: [
        .target(name: "KombuchaCore"),
        .target(name: "CSMC"),
        .target(name: "SMCKit", dependencies: ["CSMC"]),
        .target(name: "HelperProtocol"),
        .target(name: "HelperCore", dependencies: ["SMCKit", "HelperProtocol"]),
        .testTarget(name: "KombuchaCoreTests", dependencies: ["KombuchaCore"]),
        .testTarget(name: "SMCKitTests", dependencies: ["SMCKit", "CSMC"]),
        .testTarget(name: "HelperProtocolTests", dependencies: ["HelperProtocol"]),
        .testTarget(name: "HelperCoreTests", dependencies: ["HelperCore", "HelperProtocol", "SMCKit"]),
    ]
)
