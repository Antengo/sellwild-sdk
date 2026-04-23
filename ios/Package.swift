// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SellwildSDK",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "SellwildSDK",
            targets: ["SellwildSDK"]
        ),
    ],
    targets: [
        .target(
            name: "SellwildSDK",
            path: "Sources/SellwildSDK"
        ),
        .testTarget(
            name: "SellwildSDKTests",
            dependencies: ["SellwildSDK"],
            path: "Tests/SellwildSDKTests"
        ),
    ]
)
