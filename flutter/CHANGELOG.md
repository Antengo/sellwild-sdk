## 1.2.0

- **First-class remote config**: `SellwildSDK.configure(partnerCode:, slug:)` returns a fully-populated `SellwildConfig` from the Sellwild CDN at app launch. Partner code + slug = working SDK.
- `listingsUrl` is now optional. When unset, derives a deterministic default from `partnerCode` via `SellwildConfig.effectiveListingsUrl`.
- Silent fallback on any network/timeout/404 failure — ads still render with deterministic defaults.

## 1.1.0

- Remote config support — `buildConfigWithRemote()` fetches partner config from the Sellwild CDN
- Falls back silently to static config if the remote fetch fails

## 1.0.0

- Initial release
- Banner ads (320x50, 300x250, 728x90)
- Marketplace widget with listing cards
- Listings API client
- Server-side header bidding via Prebid Server
