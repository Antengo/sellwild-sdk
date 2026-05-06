## 1.3.0

- **Native banner path**: `SellwildAdView` now hosts a native Google Mobile Ads `AdManagerBannerView` (iOS) / `AdManagerAdView` (Android). Banner ads run a native Prebid Mobile auction and render natively — no WebView in the ad path.
- React Native `SellwildBanner` bridges to the native iOS/Android `SellwildAdView` via `RCTViewManager` (no WebView).
- Flutter `SellwildNativeBanner` bridges to the native iOS/Android `SellwildAdView` via platform channels.
- `SellwildWidget` (marketplace listings) still uses WebView — that surface is intentional and unchanged.
- iOS now requires Xcode 16+ (PrebidMobile 3.x dependency); Android `minSdk` raised to 23 (Prebid Mobile 3.x requirement).

## 1.2.0

- **First-class remote config**: `SellwildSDK.configure(partnerCode:, slug:)` returns a fully-populated `SellwildConfig` from the Sellwild CDN at app launch. Partner code + slug = working SDK.
- **Passthrough remote JSON**: every key from the remote-config document is preserved on `SellwildConfig.remoteJson` and forwarded verbatim to the WebView widget as a data attribute. New CMS-defined bidders and settings reach partners without an SDK release.
- `listingsUrl` is now optional. When unset, derives a deterministic default from `partnerCode` via `SellwildConfig.effectiveListingsUrl`.
- Silent fallback on any network/timeout/404 failure — ads still render with deterministic defaults.
- Typed bidder fields are deprecated in favour of `remoteJson`; they will be removed in 2.0.

## 1.1.0

- Remote config support — `buildConfigWithRemote()` fetches partner config from the Sellwild CDN
- Falls back silently to static config if the remote fetch fails

## 1.0.0

- Initial release
- Banner ads (320x50, 300x250, 728x90)
- Marketplace widget with listing cards
- Listings API client
- Server-side header bidding via Prebid Server
