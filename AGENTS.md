# AGENTS.md

## Core

The WebView widget (`SellwildWidgetView` / `SellwildWidget` — Prebid.js inside a WebView) has been REMOVED from iOS, Android, and React Native. It could not produce the CPMs the deal needs. Native (Prebid Mobile + GAM via `SellwildAdView` / `SellwildAdBanner` / `SellwildFeedView` / `SellwildNativeAdView`) is the only supported path. DO NOT reintroduce a WebView ad or listings surface.

## Release Checklist — iOS SDK

**Full release procedure lives in [RELEASING.md](./RELEASING.md) — follow it step by step. A release is not done until a partner can install it from a clean machine.**

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

The SDK depends on `SellwildPrebid` and `SellwildPrebidGAMEventHandlers` from `Antengo/sellwild-prebid-mobile-ios`. As of 1.4.2 all three pods ARE on the public CocoaPods trunk, so partners just need:

```ruby
pod 'SellwildSDK', '~> 1.4.2'
```

**Publishing a new version to trunk** (dependency order matters):

```bash
# 1. In the fork repo: bump all 4 podspec versions, tag, push
pod trunk push SellwildPrebid.podspec --allow-warnings
pod trunk push SellwildPrebidGAMEventHandlers.podspec --allow-warnings --synchronous
# 2. In this repo: bump podspec + Package.swift pins, tag, push
pod trunk push SellwildSDK.podspec --allow-warnings --synchronous
```

Gotchas learned the hard way:
- Trunk publishes go to the Specs git repo immediately, but `cdn.cocoapods.org` (jsDelivr) shard files can stay stale for 30+ min if the purge webhook fails. Manually purge: `curl https://purge.jsdelivr.net/cocoa/all_pods_versions_X_Y_Z.txt` (shard = first 3 hex chars of `md5(podname)`).
- Verify with a real `pod install --repo-update` in a scratch project before telling partners it's live.
- Never move an existing tag — cut a new version.
