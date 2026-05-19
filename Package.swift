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
        // Prebid Mobile SDK (native auction). Supports 3.0.1 through 3.x.
        // (3.0.0 has an upstream mixed-language source file issue; bump to 3.0.1+.)
        .package(url: "https://github.com/prebid/prebid-mobile-ios.git", "3.0.1"..<"4.0.0"),
        // Google Mobile Ads SDK (native render). Supports 12.0 through 13.x.
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", "12.0.0"..<"14.0.0"),
    ],
    targets: [
        .target(
            name: "SellwildSDK",
            dependencies: [
                .product(name: "PrebidMobile", package: "prebid-mobile-ios"),
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
