# @sellwild/sdk-core

Core types, API client, and ad configuration for the Sellwild mobile advertising SDK.

This package provides the shared foundation used by [`@sellwild/react-native-sdk`](https://www.npmjs.com/package/@sellwild/react-native-sdk) and the Sellwild web widget. You typically don't install this directly — it's included as a dependency of the platform SDKs.

## What's Inside

- **`SellwildConfig`** — Full SDK configuration type
- **`buildConfig()`** — Build a config from partial options with sensible defaults
- **`fetchListings()`** — Fetch marketplace listings from the Sellwild API
- **`fetchTagCacheListings()`** — Fetch listings by keyword tags
- **`eventQueue`** — Analytics event batching and delivery
- **`getAdPlacements()`** — Generate ad placement configurations from config

## Documentation

Full SDK docs: [sdk.sellwild.com](https://sdk.sellwild.com)
