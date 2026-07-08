# AGENTS.md

## Core

The WebView widget (`SellwildWidgetView` — Prebid.js inside a WebView) WILL NOT PRODUCE THE CPMs NECESSARY FOR THE DEAL. WE NEED NATIVE (Prebid Mobile + GAM via `SellwildAdView` / `SellwildAdBanner`).

## Release Checklist — iOS SDK

When releasing a new iOS SDK version, you MUST update BOTH distribution paths:

1. **Package.swift** — SPM users
2. **SellwildSDK.podspec** — CocoaPods users

If the release involves dependency changes (e.g., switching from `PrebidMobile` to `SellwildPrebid`), verify BOTH paths resolve correctly:

```bash
# SPM: resolve dependencies
swift package resolve

# CocoaPods: lint the podspec
pod spec lint SellwildSDK.podspec --allow-warnings
```

**DO NOT** declare a release complete until you've verified both SPM and CocoaPods work. WeatherBug and other partners use CocoaPods.

### Namespace-Shaded Prebid (1.4.2+)

The SDK depends on `SellwildPrebid` and `SellwildPrebidGAMEventHandlers` from `Antengo/sellwild-prebid-mobile-ios`. These are NOT on the public CocoaPods trunk. Partners must use direct git references in their Podfile:

```ruby
pod 'SellwildPrebid', :git => 'https://github.com/Antengo/sellwild-prebid-mobile-ios.git', :tag => '1.4.2'
pod 'SellwildPrebidGAMEventHandlers', :git => 'https://github.com/Antengo/sellwild-prebid-mobile-ios.git', :tag => '1.4.2'
pod 'SellwildSDK', :git => 'https://github.com/Antengo/sellwild-sdk.git', :tag => '1.4.2'
```

When bumping SDK version, also bump the tag in the fork's podspecs and create a matching tag there.
