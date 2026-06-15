# @sellwild/react-native-sdk

Sellwild mobile advertising SDK for React Native. Server-side header bidding through Prebid Server — one SDK, sub-200ms auctions, no client-side bidder SDKs.

## Install

```bash
npm install @sellwild/react-native-sdk react-native-webview
cd ios && pod install && cd ..
```

### Android: Kotlin stdlib fix (RN 0.74)

If your Android build fails with "incompatible version of Kotlin" errors, add this to your `android/build.gradle`:

```groovy
subprojects {
    afterEvaluate {
        configurations.all {
            resolutionStrategy {
                force "org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion"
                force "org.jetbrains.kotlin:kotlin-stdlib-common:$kotlinVersion"
                force "org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlinVersion"
                force "org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlinVersion"
            }
        }
    }
}
```

This forces transitive dependencies (Prebid Mobile, GMA) to use your app's Kotlin version instead of pulling in incompatible newer versions.

## Quick Start

```tsx
import React from 'react';
import { SafeAreaView } from 'react-native';
import { SellwildBanner, buildConfig } from '@sellwild/react-native-sdk';

const config = buildConfig({
  partnerCode: 'your-partner',
  listingsUrl: 'https://your-cms-or-cache.example.com/listings.json',
  appBundleId: 'com.yourcompany.yourapp',
  appStoreUrl: 'https://play.google.com/store/apps/details?id=com.yourcompany.yourapp',
  prebidServer: {
    accountId: 'your-account',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
    timeout: 1500,
  },
});

export default function App() {
  return (
    <SafeAreaView style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <SellwildBanner
        config={config}
        size="300x250"
        onImpression={() => console.log('Ad impression')}
        onError={(err) => console.warn('Ad error:', err.message)}
      />
    </SafeAreaView>
  );
}
```

## Components

- **`SellwildBanner`** — Display ad (300x250, 320x50, 728x90)
- **`SellwildWidget`** — Full marketplace widget with listings and ads
- **`SellwildListingCard`** — Individual listing card component
- **`useSellwildListings`** — Hook for fetching listings data

## Documentation

Full integration guide: [sdk.sellwild.com](https://sdk.sellwild.com/guide/react-native)
