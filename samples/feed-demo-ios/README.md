# SellwildFeed iOS demo

Minimal standalone iOS app that boots `SellwildSDK.configure()` with the
WeatherBug partner code and renders `SellwildFeed` (SwiftUI) against the live
CDN config + cache listings.

## Setup

Project is generated via [xcodegen](https://github.com/yonsm/XcodeGen) from
`project.yml`. To (re)generate:

```sh
brew install xcodegen
cd samples/feed-demo-ios
xcodegen generate
```

Then open `FeedDemo.xcodeproj` in Xcode (or build from CLI):

```sh
xcodebuild -project FeedDemo.xcodeproj \
  -scheme FeedDemo \
  -destination "platform=iOS Simulator,name=iPhone 15" \
  build
```

The project depends on the local SDK via a Swift Package reference
(`../../ios`), so no Pod install is required.

## What you should see

Header bar (`Marketplace` + `Powered by Sellwild`), then a vertical feed
following the `col1` token schedule injected by `FeedDemoApp.boot()` (default
`BLGLGLGLGLG`):

- `B` → 320×50 banner (Google test ad unit fallback)
- `L` → listing card (full-bleed image, title, price, seller line)
- `G` → 300×250 MREC (adaptive-banner test ad unit fallback)

Schedule, theme, listings URL, and zone IDs are all CDN-driven via
`SellwildSDK.configure()`. The demo only injects token overrides so the schedule
is visible without waiting on a CMS publish.
