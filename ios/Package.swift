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
        // Prebid Mobile SDK (native auction).
        .package(url: "https://github.com/prebid/prebid-mobile-ios.git", from: "3.3.0"),
        // Google Mobile Ads SDK (native render).
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", from: "13.0.0"),
    ],
    targets: [
        .target(
            name: "SellwildSDK",
            dependencies: [
                .product(name: "PrebidMobile", package: "prebid-mobile-ios"),
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "Sources/SellwildSDK"
        ),
        .testTarget(
            name: "SellwildSDKTests",
            dependencies: ["SellwildSDK"],
            path: "Tests/SellwildSDKTests"
        ),
    ]
)
