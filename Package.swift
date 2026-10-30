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
        .package(url: "https://github.com/Antengo/sellwild-prebid-mobile-ios.git", exact: "1.4.5"),
        // Google Mobile Ads SDK (native render). Supports 12.0 through 13.x.
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", "12.0.0"..<"14.0.0"),
    ],
    targets: [
        .target(
            name: "SellwildSDK",
            dependencies: [
                .product(name: "SellwildPrebidSDK", package: "sellwild-prebid-mobile-ios"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                // iOS-only binary (no macOS slice). Code guards with canImport.
                .target(name: "Boltive", condition: .when(platforms: [.iOS])),
            ],
            path: "ios/Sources/SellwildSDK"
        ),
        // Boltive ad-quality SDK (proprietary binary, also the `Boltive` pod).
        // Dormant unless MOBILE_BOLTIVE_ENABLED is on. Bump url + checksum
        // together: `swift package compute-checksum <zip>`.
        .binaryTarget(
            name: "Boltive",
            url: "https://d29z9h4vafd34g.cloudfront.net/ios/boltive-ios-sdk-1.3.12.zip",
            checksum: "0d8c0efbeb54339432c70694afa6c1660f056caa747da867f012fb2ac8335e8f"
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
