import React from 'react'
import {
  Platform,
  requireNativeComponent,
  StyleProp,
  StyleSheet,
  Text,
  UIManager,
  View,
  ViewStyle,
  NativeSyntheticEvent,
} from 'react-native'
import type { SellwildConfig, SellwildListing } from '@sellwild/sdk-core'

// ─── Native component bridge ─────────────────────────────────────────────────
//
// SellwildFeed is the "all-in-one" native surface: a single-column scroll
// of native listing cards interleaved with native Prebid + GAM ads,
// scheduled by the CDN-published COL1 token string. There is **no
// WebView** in this surface — every row is native on both platforms.
//
// iOS:     SellwildFeedView (UITableView-backed)
// Android: com.sellwild.sdk.SellwildFeedView (RecyclerView-backed)
//
// This component is the drop-in native replacement for the WebView-based
// <SellwildWidget>. Same one-component integration shape; native rails.

const NATIVE_NAME = 'SellwildFeedView'

interface NativeFeedProps {
  config: object
  style?: StyleProp<ViewStyle>
  onFeedLoaded?: (e: NativeSyntheticEvent<{}>) => void
  onListingTap?: (e: NativeSyntheticEvent<{ listing: SellwildListing }>) => void
  onAdImpression?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onAdClicked?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onFeedError?: (e: NativeSyntheticEvent<{ message: string }>) => void
}

const NativeFeed = (() => {
  // requireNativeComponent crashes loudly if the view manager isn't
  // registered. Probe first so we can render a friendly fallback on
  // platforms where the bridge isn't in this build yet.
  const config = UIManager.getViewManagerConfig?.(NATIVE_NAME)
  if (!config) {
    return null
  }
  return requireNativeComponent<NativeFeedProps>(NATIVE_NAME)
})()

// ─── Public component ────────────────────────────────────────────────────────

export interface SellwildFeedProps {
  /**
   * Resolved Sellwild config from `configure()`. The native feed reads
   * the COL1 schedule, listings URL, ad zones, and theme out of this.
   */
  config: SellwildConfig

  /** Optional style override. The feed expands to its container by default. */
  style?: ViewStyle

  /** Fired once after the initial listings fetch resolves successfully. */
  onLoad?: () => void

  /**
   * Fired when a listing card is tapped. Return `true` to consume the
   * event; return `false` (or omit) to let the SDK open `listing.url`
   * in the platform in-app browser (Custom Tabs / SFSafariViewController).
   */
  onListingTap?: (listing: SellwildListing) => boolean | void

  /** Fired when a native ad row records an impression. */
  onAdImpression?: (zoneId: string) => void

  /** Fired when a native ad row is clicked. */
  onAdClicked?: (zoneId: string) => void

  /** Fired when the listings fetch fails or a row fails to render. */
  onError?: (error: Error) => void
}

export function SellwildFeed({
  config,
  style,
  onLoad,
  onListingTap,
  onAdImpression,
  onAdClicked,
  onError,
}: SellwildFeedProps) {
  if (!NativeFeed) {
    // Native module not registered. Most common cause: the host app was
    // built before the @sellwild/react-native-sdk autolink ran, or this
    // is being rendered in a JS-only test environment.
    return (
      <View style={[styles.fill, style, __DEV__ ? styles.devPlaceholder : undefined]}>
        {__DEV__ ? (
          <Text style={styles.devText}>
            Sellwild native feed not available on {Platform.OS} (yet)
          </Text>
        ) : null}
      </View>
    )
  }

  // Pass the fields the native feed reads, plus the raw CDN payload
  // under `remote`. The native bridge re-runs the CDN decoder against
  // `remote` to populate feed-specific fields (COL1 schedule, bgColor,
  // mobileZids, mobileBannerZid, listingsUrl), so we don't need to
  // mirror every field as a typed property on the JS side.
  //
  // Note: TS core uses `adRefreshInterval` (ms); the native side
  // reads it as `adRefreshIntervalMs`. The bridge translates.
  const nativeConfig: Record<string, unknown> = {
    partnerCode: config.partnerCode,
    slug: config.slug,
    appBundleId: config.appBundleId,
    appStoreUrl: config.appStoreUrl,
    geo: config.geo,
    gamTag: config.gamTag,
    debug: config.debug,
    pbsDebug: config.pbsDebug,
    adRefreshMax: config.adRefreshMax,
    adRefreshMaxMobile: config.adRefreshMaxMobile,
    adRefreshIntervalMs: config.adRefreshInterval,
    prebidServer: config.prebidServer,
    remote: config.remote,
    listingsUrl: config.listingsUrl,
    priceColor: config.priceColor,
    bannerZid: config.bannerZid,
    bottomBannerZid: config.bottomBannerZid,
    mobileBannerZid: config.mobileBannerZid,
    mobileZids: config.mobileZids,
  }

  return (
    <NativeFeed
      style={[styles.fill, style]}
      config={nativeConfig}
      onFeedLoaded={() => onLoad?.()}
      onListingTap={(e: NativeSyntheticEvent<{ listing: SellwildListing }>) => {
        onListingTap?.(e.nativeEvent.listing)
      }}
      onAdImpression={(e: NativeSyntheticEvent<{ zoneId: string }>) => {
        onAdImpression?.(e.nativeEvent.zoneId)
      }}
      onAdClicked={(e: NativeSyntheticEvent<{ zoneId: string }>) => {
        onAdClicked?.(e.nativeEvent.zoneId)
      }}
      onFeedError={(e: NativeSyntheticEvent<{ message: string }>) => {
        const msg = e.nativeEvent?.message ?? 'Feed failed'
        onError?.(new Error(msg))
      }}
    />
  )
}

const styles = StyleSheet.create({
  fill: {
    flex: 1,
  },
  devPlaceholder: {
    backgroundColor: '#FEE2E2',
    borderWidth: 1,
    borderColor: '#FCA5A5',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 12,
  },
  devText: {
    color: '#991B1B',
    fontSize: 12,
    textAlign: 'center',
  },
})
