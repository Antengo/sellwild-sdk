# Migration Guide: SellwildWidget → SellwildFeed

This guide walks you through migrating from the WebView-based `<SellwildWidget>` to the native `<SellwildFeed>` component.

---

## Why Migrate?

| Feature | SellwildWidget (WebView) | SellwildFeed (Native) |
|---------|--------------------------|----------------------|
| Rendering | WebView (HTML/JS) | Native (UITableView / RecyclerView) |
| Ad monetization | Lower CPMs | **Higher CPMs** (native demand) |
| Listing tap handling | `window.open()` / `<a href>` issues | Native tap with callback |
| Performance | JS bridge overhead | Native scrolling, 60fps |
| Memory | WebView process | Lean native views |
| Pull-to-refresh | JS-based | Native gesture |

**Bottom line:** `SellwildFeed` delivers better ad revenue and a smoother user experience.

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

**Before (WebView):**
```tsx
import { SellwildWidget } from '@sellwild/react-native-sdk';
```

**After (Native):**
```tsx
import { SellwildFeed } from '@sellwild/react-native-sdk';
```

---

## Step 2: Replace Component

**Before (WebView):**
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
    // Return true to consume the tap (handle yourself)
    // Return false/undefined to let SDK open in-app browser
    console.log('Tapped:', listing.title);
    return false; // SDK opens listing.url
  }}
  onAdImpression={(zoneId) => console.log('Ad impression:', zoneId)}
  onAdClicked={(zoneId) => console.log('Ad clicked:', zoneId)}
  onError={(err) => console.warn('Feed error:', err.message)}
/>
```

---

## Step 3: Adjust Tap Handling

The key behavioral difference is in `onListingTap`:

| Behavior | SellwildWidget | SellwildFeed |
|----------|----------------|--------------|
| Default tap action | Opens URL via WebView `<a>` tag | Opens URL in in-app browser (Custom Tabs / SFSafariViewController) |
| Custom handling | Not reliable (WebView navigation issues) | Return `true` from callback to consume tap |

### Example: Custom Product Detail Screen

```tsx
import { useNavigation } from '@react-navigation/native';

function MarketplaceFeed({ config }) {
  const navigation = useNavigation();

  return (
    <SellwildFeed
      config={config}
      style={{ flex: 1 }}
      onListingTap={(listing) => {
        // Navigate to your own product detail screen
        navigation.navigate('ProductDetail', { 
          productId: listing.id,
          title: listing.title,
          url: listing.url,
        });
        return true; // Consume tap — SDK won't open browser
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
    // Log analytics, then let SDK open the URL
    analytics.track('listing_tap', { id: listing.id });
    return false; // SDK opens in-app browser
  }}
/>
```

---

## Step 4: Remove react-native-webview (Optional)

If `<SellwildWidget>` was your only use of `react-native-webview`, you can remove it:

```bash
npm uninstall react-native-webview
cd ios && pod install && cd ..
```

This reduces your bundle size and removes the WebView dependency.

> **Note:** Keep `react-native-webview` if other parts of your app use it.

---

## API Reference

### SellwildFeed Props

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `config` | `SellwildConfig` | ✅ | Config from `configure()` or `buildConfig()` |
| `style` | `ViewStyle` | | Optional style override |
| `onLoad` | `() => void` | | Fired when listings fetch completes |
| `onListingTap` | `(listing: SellwildListing) => boolean \| void` | | Tap handler. Return `true` to consume. |
| `onAdImpression` | `(zoneId: string) => void` | | Fired on ad impression |
| `onAdClicked` | `(zoneId: string) => void` | | Fired on ad click |
| `onError` | `(error: Error) => void` | | Fired on fetch/render failure |

### SellwildListing Object

```ts
interface SellwildListing {
  id: string;
  title: string;
  url: string;           // Tap destination URL
  price?: number;
  currency?: string;     // 'USD', 'EUR', etc.
  photoUrl?: string;
  sellerFirstName?: string;
  sellerLastInitial?: string;
}
```

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

### Before (WebView-based)

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
