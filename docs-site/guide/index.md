# Introduction

The Sellwild SDK delivers programmatic display and video ads into native mobile applications through a managed Prebid Server instance. Banner auctions run through native Prebid Mobile and render in `AdManagerBannerView` / `AdManagerAdView` — no WebView in the ad path, no on-device JavaScript waterfall, no SDK bloat.

::: tip What's new in 1.3.0
- **Banner ads now render natively** through the Google Mobile Ads SDK + Prebid Mobile. The ad path no longer touches a WebView.
- **`SellwildWidget` (marketplace listings) still uses a WebView** for listing rendering — that's intentional and unchanged.
- **Action required for upgraders.** iOS now requires **Xcode 16+** (PrebidMobile 3.x). Android `minSdk` is raised to **23**. iOS apps must set `GADApplicationIdentifier` in `Info.plist`; Android apps must set the `com.google.android.gms.ads.APPLICATION_ID` `<meta-data>` entry in `AndroidManifest.xml`. See the platform guides for details.
:::

## How It Works

<ArchitectureDiagram />

## Why Server-Side

| | Client-Side SDKs | Sellwild (Server-Side) |
|---|---|---|
| **Integration** | 10-40 individual SDKs | 1 SDK |
| **Auction** | On-device, sequential | Server-side, parallel |
| **Latency** | 2-5s per waterfall | <200ms total |
| **App Size** | +30-80 MB | +2 MB |
| **Device IDs** | Each SDK reads separately | Passed once, securely |
| **Updates** | App Store release required | Server config change |
| **Reporting** | Fragmented across SSPs | Unified dashboard |

## Supported Platforms

| Platform | Language | Min Version | Package Manager |
|----------|----------|-------------|-----------------|
| iOS | Swift 5.5 | iOS 13+ | SPM / CocoaPods |
| Android | Kotlin | API 21+ | Gradle (Maven) |
| React Native | TypeScript | RN 0.70+ | npm / yarn |
| Flutter | Dart 3 | Flutter 3.10+ | pub.dev |

## Ad Formats

| Format | Size | Placement |
|--------|------|-----------|
| Banner | 320x50 | Top/bottom of screen |
| MREC | 300x250 | In-feed, between content |
| Leaderboard | 728x90 | Tablet top/bottom |
| Interstitial | Fullscreen | Between screens |
| Video | 300x250, 320x480 | In-feed, interstitial |
| Native Listings | Flexible | In-feed marketplace cards |

## Next Steps

Choose your platform to get started:

- [iOS (Swift)](/guide/ios) — Swift Package Manager or CocoaPods
- [Android (Kotlin)](/guide/android) — Gradle dependency
- [React Native](/guide/react-native) — npm package
- [Flutter](/guide/flutter) — pub.dev package

Or learn about the ad server:

- [Prebid Server](/guide/prebid-server) — SSP configuration, GDPR, auction telemetry
- [Remote Config](/guide/configuration#remote-config) — change ad zones, refresh intervals, and waterfall partners without an app update
