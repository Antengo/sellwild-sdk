// swift-tools-version:5.9
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
    dependencies: [
        // SellwildPrebidSDK: Namespace-shaded fork of Prebid Mobile SDK.
        // Allows Sellwild ads to coexist with host app's own Prebid implementation.
        .package(url: "https://github.com/Antengo/sellwild-prebid-mobile-ios.git", exact: "1.4.4"),
        // Google Mobile Ads SDK (native render). Supports 12.0 through 13.x.
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", "12.0.0"..<"14.0.0"),
    ],
    targets: [
        .target(
            name: "SellwildSDK",
            dependencies: [
                .product(name: "SellwildPrebidSDK", package: "sellwild-prebid-mobile-ios"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "ios/Sources/SellwildSDK"
        ),
        .testTarget(
            name: "DocsVerifyTests",
            dependencies: ["SellwildSDK"],
            path: "ios/Tests/DocsVerifyTests"
        ),
        .testTarget(
            name: "SellwildSDKTests",
            dependencies: ["SellwildSDK"],
            path: "ios/Tests/SellwildSDKTests"
        ),
    ]
)
