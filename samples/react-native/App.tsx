/**
 * Sellwild React Native SDK — Runnable Sample App
 *
 * How to run:
 *   1. Create a new React Native project:
 *        npx react-native@latest init SellwildDemo --template react-native-template-typescript
 *   2. Install the SDK (1.3.0+):
 *        npm install @sellwild/react-native-sdk@^1.3.0
 *        cd ios && pod install
 *
 *      As of 1.3.0 the RN SDK bridges to native iOS / Android `SellwildAdView`,
 *      which transitively pull in PrebidMobile + Google Mobile Ads. iOS apps
 *      need Xcode 16+ and a `GADApplicationIdentifier` in Info.plist; Android
 *      apps need `minSdk 23` and a `com.google.android.gms.ads.APPLICATION_ID`
 *      `<meta-data>` entry in AndroidManifest.xml. See the platform guides at
 *      https://sdk.sellwild.com/guide/ios and /guide/android.
 *   3. Replace App.tsx with this file.
 *   4. Run: npx react-native run-ios  OR  npx react-native run-android
 *
 * Note: Replace 'YOUR_PARTNER_CODE' / 'your-partner-slug' with real values
 * from sdk@sellwild.com before running.
 */

import React, { useCallback, useEffect, useState } from 'react'
import {
  Alert,
  FlatList,
  Linking,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
} from 'react-native'
import {
  SellwildWidget,
  SellwildBanner,
  SellwildListingCard,
  useSellwildListings,
  buildConfig,
  configure,
  clearRemoteConfigCache,
} from '@sellwild/react-native-sdk'
import type { SellwildListing, SellwildConfig, PartialSellwildConfig } from '@sellwild/react-native-sdk'

// ─── Config ───────────────────────────────────────────────────────────────────
//
// Ad path (1.3.0+):
//   `SellwildBanner` is a native component. The RN SDK bridges to the native
//   iOS / Android `SellwildAdView`, which runs a NATIVE Prebid Mobile auction
//   and renders the winner into a NATIVE `AdManagerBannerView` (iOS) or
//   `AdManagerAdView` (Android). There is no WebView in the banner ad path.
//   The marketplace `SellwildWidget` still renders listings inside a WebView;
//   that surface is intentional and unchanged.
//
// Remote config (the first-class path, 1.2.0+):
//   `configure(partnerCode, slug)` fetches every runtime field from the
//   Sellwild CDN (https://widget.sellwild.com/app/{partnerCode}/{slug}.json)
//   and returns a fully-built `SellwildConfig`. Bidders, refresh limits,
//   geo-blocking, app identity, ad zones, and compliance flags are all
//   toggled from the Sellwild CMS without an app update. On any
//   network/timeout/404 failure the call falls back to deterministic defaults
//   so ads still render. See `NativeListingsScreen` below for the canonical
//   usage.

// Static fallback config (used when you can't make a network call before
// rendering ads). 1.2.0+ makes `listingsUrl` optional — leave it unset and
// the SDK derives a default from `partnerCode`.
const BASE_CONFIG: PartialSellwildConfig = {
  partnerCode: 'YOUR_PARTNER_CODE',

  // Use your actual iOS bundle ID or Android package name. Surfaces as
  // `ortb2.app.bundle` in the Prebid Mobile auction.
  appBundleId: 'com.mycompany.myapp',
  appStoreUrl: 'https://apps.apple.com/app/idXXXXXXXXX',

  // Uncomment to override the GAM ad unit served on the native banner:
  // gamTag: '/12345678/your-ad-unit',

  // Uncomment to pin specific zone IDs (otherwise the CDN config wins):
  // bannerZid: '98765',
  // mobileZids: ['11111', '22222'],

  adRefreshMaxMobile: 5,
  adRefreshInterval: 30000,
  debug: __DEV__,
}

// ─── Screen: Marketplace Widget (WebView-rendered listings) ───────────────────
// `SellwildWidget` renders the full marketplace listing surface inside a
// WebView. This is intentional — only banner ads moved to native rendering in
// 1.3.0; the marketplace listing UI is unchanged.

function WebViewWidgetScreen() {
  const handleListingPress = useCallback((listing: SellwildListing) => {
    const url = listing.url
    if (url) {
      Linking.openURL(url).catch(() => Alert.alert('Cannot open URL', url))
    }
  }, [])

  const handleAdImpression = useCallback((zoneId: string | number) => {
    console.log('[Sellwild] Ad impression, zoneId:', zoneId)
  }, [])

  return (
    <SellwildWidget
      config={BASE_CONFIG}
      style={styles.fullFlex}
      onListingPress={handleListingPress}
      onAdImpression={handleAdImpression}
      onError={(err) => console.error('[Sellwild] Widget error:', err.message)}
      onLoad={() => console.log('[Sellwild] Widget loaded')}
    />
  )
}

// ─── Screen: Native Listing Cards + Banner ────────────────────────────────────

function NativeListingsScreen() {
  // ─── Remote Config (the first-class path) ──────────────────────────────
  // `configure(partnerCode, slug)` fetches every runtime field from
  // https://widget.sellwild.com/app/{partnerCode}/{slug}.json. Bidders,
  // refresh limits, geo-blocking, app identity, ad zones, compliance flags
  // — all toggled from the Sellwild CMS without an app update. Silent
  // fallback to deterministic defaults on any network/timeout/404 failure.
  const [config, setConfig] = useState<SellwildConfig | null>(null)

  useEffect(() => {
    configure('YOUR_PARTNER_CODE', 'your-partner-slug', { timeout: 5000 })
      .then(setConfig)
  }, [])

  const { listings, loading, error, refresh } = useSellwildListings(
    config ?? buildConfig(BASE_CONFIG),
  )

  const handlePress = useCallback((listing: SellwildListing) => {
    Alert.alert(listing.title, listing.url ?? 'No URL', [
      { text: 'Open', onPress: () => listing.url && Linking.openURL(listing.url) },
      { text: 'Cancel', style: 'cancel' },
    ])
  }, [])

  if (!config) {
    return (
      <View style={styles.center}>
        <Text>Loading config…</Text>
      </View>
    )
  }

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={styles.errorText}>Failed to load listings</Text>
        <Text style={styles.errorDetail}>{error.message}</Text>
        <TouchableOpacity style={styles.button} onPress={refresh}>
          <Text style={styles.buttonText}>Retry</Text>
        </TouchableOpacity>
      </View>
    )
  }

  return (
    <View style={styles.fullFlex}>
      {/* 320×50 banner at top */}
      <SellwildBanner
        config={config}
        size="320x50"
        zoneId={config.bannerZid ?? 'ZONE_ID'}
        onImpression={() => console.log('[Sellwild] Banner impression')}
        onError={(err) => console.warn('[Sellwild] Banner error:', err.message)}
        style={styles.banner}
      />

      <FlatList
        data={listings}
        numColumns={2}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContent}
        refreshing={loading}
        onRefresh={refresh}
        renderItem={({ item }) => (
          <SellwildListingCard
            listing={item}
            config={config}
            onPress={handlePress}
            style={styles.card}
          />
        )}
        ListEmptyComponent={
          loading ? null : (
            <View style={styles.center}>
              <Text>No listings found</Text>
            </View>
          )
        }
      />

      {/* 300×250 MREC at bottom */}
      <SellwildBanner
        config={config}
        size="300x250"
        zoneId={config.mobileZids?.[0] ?? 'ZONE_ID'}
        onImpression={() => console.log('[Sellwild] MREC impression')}
        style={styles.mrecBanner}
      />
    </View>
  )
}

// ─── Root App ─────────────────────────────────────────────────────────────────

type Tab = 'webview' | 'native'

export default function App() {
  const [activeTab, setActiveTab] = useState<Tab>('webview')
  const [useNative, setUseNative] = useState(false)

  return (
    <SafeAreaView style={styles.root}>
      {/* Tab bar */}
      <View style={styles.tabBar}>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'webview' && styles.tabActive]}
          onPress={() => setActiveTab('webview')}
        >
          <Text style={[styles.tabText, activeTab === 'webview' && styles.tabTextActive]}>
            WebView Widget
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'native' && styles.tabActive]}
          onPress={() => setActiveTab('native')}
        >
          <Text style={[styles.tabText, activeTab === 'native' && styles.tabTextActive]}>
            Native Cards
          </Text>
        </TouchableOpacity>
      </View>

      {/* Content */}
      {activeTab === 'webview' ? (
        <WebViewWidgetScreen />
      ) : (
        <NativeListingsScreen />
      )}
    </SafeAreaView>
  )
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  fullFlex: {
    flex: 1,
  },
  tabBar: {
    flexDirection: 'row',
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  tab: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
  },
  tabActive: {
    borderBottomWidth: 2,
    borderBottomColor: '#0066cc',
  },
  tabText: {
    fontSize: 14,
    color: '#666',
  },
  tabTextActive: {
    color: '#0066cc',
    fontWeight: '600',
  },
  banner: {
    alignSelf: 'center',
    marginVertical: 8,
  },
  mrecBanner: {
    alignSelf: 'center',
    marginVertical: 12,
  },
  listContent: {
    padding: 8,
  },
  card: {
    margin: 6,
    flex: 1,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  errorText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#c00',
    marginBottom: 8,
  },
  errorDetail: {
    fontSize: 13,
    color: '#666',
    textAlign: 'center',
    marginBottom: 16,
  },
  button: {
    backgroundColor: '#0066cc',
    paddingHorizontal: 24,
    paddingVertical: 10,
    borderRadius: 6,
  },
  buttonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
})
