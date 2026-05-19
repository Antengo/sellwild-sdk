# sellwild_sdk

Sellwild mobile advertising SDK for Flutter. Server-side header bidding through Prebid Server — one SDK, sub-200ms auctions, no client-side bidder SDKs.

## Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  sellwild_sdk: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

class AdScreen extends StatelessWidget {
  const AdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = SellwildConfig(
      partnerCode: 'your-partner',
      listingsUrl: 'https://your-cms-or-cache.example.com/listings.json',
      appBundleId: 'com.yourcompany.yourapp',
      appStoreUrl: 'https://play.google.com/store/apps/details?id=com.yourcompany.yourapp',
      prebidServer: PrebidServerConfig(
        accountId: 'your-account',
        endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
        bidders: ['appnexus', 'pubmatic', 'ix', 'rubicon', 'openx'],
        timeout: 1500,
      ),
    );

    return Scaffold(
      body: Center(
        child: SellwildBanner(
          config: config,
          adSize: SellwildAdSize.mrec300x250,
          onImpression: () => debugPrint('Ad impression'),
          onError: (error) => debugPrint('Ad error: $error'),
        ),
      ),
    );
  }
}
```

## Components

- **`SellwildBanner`** — Display ad (300x250, 320x50, 728x90)
- **`SellwildWidget`** — Full marketplace widget with listings and ads
- **`SellwildListingCard`** — Individual listing card component
- **`SellwildAPIClient`** — API client for fetching listings

## Documentation

Full integration guide: [sdk.sellwild.com](https://sdk.sellwild.com/guide/flutter)
