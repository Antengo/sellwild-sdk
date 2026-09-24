# Migration Guide: SellwildWidget → SellwildFeed

The WebView-based `<SellwildWidget>` has been **removed** from the SDK, along with `SellwildWidgetProps` and the `react-native-webview` peer dependency. The native iOS and Android equivalents (`SellwildWidgetView`, SwiftUI `SellwildWidget`) are gone too. Apps that still import them will not compile against the current SDK.

Replace it with `<SellwildFeed>`, the all-in-one native feed. Native apps use `SellwildFeedView` (UIKit / Android Views) or `SellwildFeed` (SwiftUI / Compose). See the [iOS](/guide/ios#native-marketplace-feed-1-3-5) and [Android](/guide/android#native-marketplace-feed-1-3-5) guides.

---

## What Changes

| Feature | SellwildWidget (removed) | SellwildFeed (Native) |
|---------|--------------------------|----------------------|
| Rendering | WebView (HTML/JS) | Native (UITableView / RecyclerView) |
| Ad monetization | Lower CPMs | **Higher CPMs** (native demand) |
| Listing tap handling | `window.open()` / `<a href>` issues | Native tap with callback |
| Performance | JS bridge overhead | Native scrolling, 60fps |
| Memory | WebView process | Lean native views |
| Pull-to-refresh | JS-based | Native gesture |

`SellwildFeed` runs native Prebid Mobile + GAM demand and renders every row natively.

---

## Minimum SDK Version

- **React Native SDK:** 1.3.5+
- **iOS SDK:** 1.3.5+ (via CocoaPods)
- **Android SDK:** 1.3.5+ (via Maven)

Upgrade if needed:

```bash
npm install @sellwild/react-native-sdk@^1.4.0
cd ios && pod install --repo-update && cd ..
```

---

## Step 1: Update Imports

**Before (removed API):**
```tsx
import { SellwildWidget } from '@sellwild/react-native-sdk';
```

**After (Native):**
```tsx
import { SellwildFeed } from '@sellwild/react-native-sdk';
```

---

## Step 2: Replace Component

**Before (removed API):**
```tsx
<SellwildWidget
  config={config}
  style={{ flex: 1 }}
  onListingTap={(listing) => {
    // Handle listing tap
    console.log('Tapped:', listing.title);
  }}
  onError={(err) => console.warn(err.message)}
/>
```

**After (Native):**
```tsx
<SellwildFeed
  config={config}
  style={{ flex: 1 }}
  onLoad={() => console.log('Feed loaded')}
  onListingTap={(listing) => {
    // Notification only — the SDK opens listing.url in the in-app browser.
    // To handle navigation yourself, set `consumeListingTaps` (see Step 3).
    console.log('Tapped:', listing.title);
  }}
  onAdImpression={(zoneId) => console.log('Ad impression:', zoneId)}
  onAdClicked={(zoneId) => console.log('Ad clicked:', zoneId)}
  onError={(err) => console.warn('Feed error:', err.message)}
/>
```

---

## Step 3: Adjust Tap Handling

The key behavioral difference is in `onListingTap`:

| Behavior | SellwildWidget (removed) | SellwildFeed |
|----------|----------------|--------------|
| Default tap action | Opens URL via WebView `<a>` tag | Opens URL in in-app browser (Custom Tabs / SFSafariViewController) |
| Custom handling | Not reliable (WebView navigation issues) | Set the `consumeListingTaps` prop; the SDK then only fires `onListingTap` |

> The `onListingTap` return value is ignored: React Native delivers native events to JS asynchronously, after the tap has already been handled, so a callback can't veto the SDK's navigation. Use the `consumeListingTaps` prop instead.

### Example: Custom Product Detail Screen

```tsx
import { useNavigation } from '@react-navigation/native';

function MarketplaceFeed({ config }) {
  const navigation = useNavigation();

  return (
    <SellwildFeed
      config={config}
      style={{ flex: 1 }}
      consumeListingTaps // SDK won't open the browser
      onListingTap={(listing) => {
        // Navigate to your own product detail screen
        navigation.navigate('ProductDetail', { 
          productId: listing.id,
          title: listing.title,
          url: listing.url,
        });
      }}
    />
  );
}
```

### Example: Let SDK Handle Navigation

```tsx
<SellwildFeed
  config={config}
  style={{ flex: 1 }}
  onListingTap={(listing) => {
    // Log analytics; the SDK opens the in-app browser (default)
    analytics.track('listing_tap', { id: listing.id });
  }}
/>
```

---

## Step 4: Remove react-native-webview

The SDK no longer depends on `react-native-webview`. If `<SellwildWidget>` was your only use of it, remove it:

```bash
npm uninstall react-native-webview
cd ios && pod install && cd ..
```

> **Note:** Keep `react-native-webview` if other parts of your app use it.

---

## API Reference

### SellwildFeed Props

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `config` | `SellwildConfig` | Yes | Config from `configure()` or `buildConfig()` |
| `style` | `ViewStyle` | | Optional style override |
| `onLoad` | `() => void` | | Fired when listings fetch completes |
| `consumeListingTaps` | `boolean` | | Default `false`. When `true`, the SDK does not open the in-app browser on listing tap — handle navigation in `onListingTap`. |
| `onListingTap` | `(listing: SellwildListing) => void` | | Tap notification. Return value is ignored; use `consumeListingTaps` to take over navigation. |
| `onAdImpression` | `(zoneId: string) => void` | | Fired on ad impression |
| `onAdClicked` | `(zoneId: string) => void` | | Fired on ad click |
| `scrollEnabled` | `boolean` | | Defaults to `true`. Set `false` to embed in a parent `ScrollView`. |
| `onContentSizeChange` | `(e: { width?: number; height: number }) => void` | | Fired when the feed's content height changes |
| `onError` | `(error: Error) => void` | | Fired on fetch/render failure |

### SellwildListing Object

See [TypeScript Reference → SellwildListing](/guide/react-native#sellwildlisting) for the full shape.

---

## Troubleshooting

### Feed shows "not available" placeholder

The native view manager isn't registered. Ensure:

1. You've run `pod install` after upgrading
2. You've rebuilt the app (not just a JS refresh)
3. Auto-linking detected the package: `npx react-native config | grep sellwild`

### Android Kotlin version errors

Add this to `android/build.gradle`:

```groovy
subprojects {
    afterEvaluate {
        configurations.all {
            resolutionStrategy {
                force "org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion"
            }
        }
    }
}
```

### Listings don't load

Check that your config has a valid `listingsUrl` or the CDN config includes `LISTINGS`:

```tsx
const config = await configure('weatherbug', 'weatherbug-weatherbug');
console.log('Listings URL:', config.listingsUrl);
```

### Ads not showing

Ensure GAM is configured:

- **iOS:** `GADApplicationIdentifier` in `Info.plist`
- **Android:** `com.google.android.gms.ads.APPLICATION_ID` in `AndroidManifest.xml`

---

## Full Migration Example

### Before (removed API)

```tsx
import React from 'react';
import { SafeAreaView } from 'react-native';
import { SellwildWidget, configure } from '@sellwild/react-native-sdk';

export default function MarketplaceScreen() {
  const [config, setConfig] = React.useState(null);

  React.useEffect(() => {
    configure('weatherbug', 'weatherbug-weatherbug').then(setConfig);
  }, []);

  if (!config) return null;

  return (
    <SafeAreaView style={{ flex: 1 }}>
      <SellwildWidget
        config={config}
        style={{ flex: 1 }}
        onError={(err) => console.warn(err)}
      />
    </SafeAreaView>
  );
}
```

### After (Native)

```tsx
import React from 'react';
import { SafeAreaView, ActivityIndicator } from 'react-native';
import { SellwildFeed, configure } from '@sellwild/react-native-sdk';

export default function MarketplaceScreen() {
  const [config, setConfig] = React.useState(null);
  const [loading, setLoading] = React.useState(true);

  React.useEffect(() => {
    configure('weatherbug', 'weatherbug-weatherbug').then(setConfig);
  }, []);

  if (!config) return <ActivityIndicator />;

  return (
    <SafeAreaView style={{ flex: 1 }}>
      <SellwildFeed
        config={config}
        style={{ flex: 1 }}
        onLoad={() => setLoading(false)}
        onListingTap={(listing) => {
          console.log('User tapped:', listing.title);
          return false; // Let SDK open in browser
        }}
        onAdImpression={(zoneId) => {
          console.log('Ad impression:', zoneId);
        }}
        onError={(err) => {
          console.warn('Feed error:', err.message);
          setLoading(false);
        }}
      />
      {loading && (
        <ActivityIndicator 
          style={{ position: 'absolute', top: '50%', left: '50%' }} 
        />
      )}
    </SafeAreaView>
  );
}
```

---

## Questions?

- **Slack:** #ext-weatherbug-sellwild
- **Email:** sdk-support@sellwild.com
- **Docs:** [sdk.sellwild.com](https://sdk.sellwild.com)
