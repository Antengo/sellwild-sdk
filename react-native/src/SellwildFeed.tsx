import React from 'react'
import {
  Platform,
  StyleProp,
  StyleSheet,
  Text,
  View,
  ViewStyle,
  NativeSyntheticEvent,
} from 'react-native'
import type { SellwildConfig, SellwildListing } from '@sellwild/sdk-core'
import { toNativeFeedConfig } from './nativeConfig'
import { nativeViewOrNull, useMissingNativeViewReport } from './nativeViews'

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
// This is the one-component marketplace surface for React Native (the
// WebView-based <SellwildWidget> has been removed).

const NATIVE_NAME = 'SellwildFeedView'

interface NativeFeedProps {
  config: object
  scrollEnabled?: boolean
  consumeListingTaps?: boolean
  style?: StyleProp<ViewStyle>
  onFeedLoaded?: (e: NativeSyntheticEvent<{}>) => void
  onFeedReady?: (e: NativeSyntheticEvent<{ listingCount: number }>) => void
  onListingTap?: (e: NativeSyntheticEvent<{ listing: SellwildListing }>) => void
  onAdImpression?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onHouseAdImpression?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onAdClicked?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onFeedError?: (e: NativeSyntheticEvent<{ message: string }>) => void
  onContentSizeChange?: (e: NativeSyntheticEvent<{ width?: number; height: number }>) => void
}

// Probed once, when this module loads. null renders the fallback view below.
const NativeFeed = nativeViewOrNull<NativeFeedProps>(NATIVE_NAME)

// ─── Public component ────────────────────────────────────────────────────────

export interface SellwildFeedProps {
  /**
   * Resolved Sellwild config from `configure()`. The native feed reads
   * the COL1 schedule, listings URL, ad zones, and theme out of this.
   */
  config: SellwildConfig

  /** Optional style override. The feed expands to its container by default. */
  style?: ViewStyle

  /**
   * When `false`, the feed's own scrolling is disabled and the component
   * sizes its own container from the reported content height, so it can be
   * embedded inside a parent `ScrollView` (single-scroll pages, e.g.
   * alongside a Taboola feed). The feed then renders every row (no
   * virtualization) and pull-to-refresh is disabled — the host drives
   * refresh. Defaults to `true`; existing full-screen integrations are
   * unaffected.
   */
  scrollEnabled?: boolean

  /**
   * Fired whenever the feed's content height changes. Use it to size the
   * feed's container when embedding with `scrollEnabled={false}`; when
   * scroll is disabled the component also applies the height itself.
   */
  onContentSizeChange?: (e: { width?: number; height: number }) => void

  /** Fired once after the initial listings fetch resolves successfully. */
  onLoad?: () => void

  /**
   * Fired after a successful fetch with the number of listings bound to the
   * feed. `listingCount === 0` means an empty / header-only render. Prefer this
   * over `onLoad` when you need to know the feed is actually populated — `onLoad`
   * also fires on an empty result.
   */
  onFeedReady?: (listingCount: number) => void

  /**
   * When `true`, listing taps are fully handled by the host app: the SDK does
   * NOT open the listing in the in-app browser (Custom Tabs /
   * SFSafariViewController) and only fires `onListingTap`. Use this to route
   * listings through your own navigation. Defaults to `false` (the SDK opens
   * the listing URL), so existing integrations are unaffected.
   */
  consumeListingTaps?: boolean

  /**
   * Fired when a listing card is tapped. This is a notification only: the
   * return value is ignored, because React Native events are delivered to JS
   * asynchronously — after the native side has already decided whether to
   * open the browser. To handle navigation yourself, set
   * `consumeListingTaps` instead.
   *
   * The `boolean` return type is kept only so existing handlers still compile;
   * it is deprecated and has no effect.
   */
  onListingTap?: (listing: SellwildListing) => boolean | void

  /** Fired when a native ad row records an impression. */
  onAdImpression?: (zoneId: string) => void

  /**
   * Fired when a house ad backfilled an empty ad row (a no-fill). NOT a paid
   * impression — track it separately. See the `MOBILE_HOUSE_AD_*` config keys.
   */
  onHouseAdImpression?: (zoneId: string) => void

  /** Fired when a native ad row is clicked. */
  onAdClicked?: (zoneId: string) => void

  /** Fired when the listings fetch fails or a row fails to render. */
  onError?: (error: Error) => void
}

export function SellwildFeed({
  config,
  style,
  scrollEnabled = true,
  consumeListingTaps = false,
  onContentSizeChange,
  onLoad,
  onFeedReady,
  onListingTap,
  onAdImpression,
  onHouseAdImpression,
  onAdClicked,
  onError,
}: SellwildFeedProps) {
  // When embedded (scrollEnabled === false) the parent ScrollView owns
  // scrolling, so we size our own container from the native-reported content
  // height rather than filling with flex:1.
  const [contentHeight, setContentHeight] = React.useState<number | null>(null)
  // Dev-only: warn once per feed about the ignored `return true`, not on every tap.
  const warnedReturnTrue = React.useRef(false)
  const embedded = scrollEnabled === false
  const containerStyle: StyleProp<ViewStyle> = embedded
    ? [contentHeight != null ? { height: contentHeight } : undefined, style]
    : [styles.fill, style]

  useMissingNativeViewReport(NATIVE_NAME, 'feed', !NativeFeed)

  if (!NativeFeed) {
    // Native module not registered. Most common cause: the host app was
    // built before the @sellwild/react-native-sdk autolink ran, or this
    // is being rendered in a JS-only test environment.
    return (
      <View style={[containerStyle, __DEV__ ? styles.devPlaceholder : undefined]}>
        {__DEV__ ? (
          <Text style={styles.devText}>
            Sellwild native feed not available on {Platform.OS} (yet)
          </Text>
        ) : null}
      </View>
    )
  }

  // The fields the native feed reads, plus the raw CDN payload under
  // `remote` (see toNativeFeedConfig).
  const nativeConfig = toNativeFeedConfig(config)

  return (
    <NativeFeed
      style={containerStyle}
      config={nativeConfig}
      scrollEnabled={scrollEnabled}
      consumeListingTaps={consumeListingTaps}
      onContentSizeChange={(e: NativeSyntheticEvent<{ width?: number; height: number }>) => {
        const { width, height } = e.nativeEvent ?? { height: 0 }
        // Only size our own container when embedded; a scrolling feed fills
        // its parent via flex:1 and doesn't need a measured height.
        if (embedded && height > 0) setContentHeight(height)
        onContentSizeChange?.({ width, height })
      }}
      onFeedLoaded={() => onLoad?.()}
      onFeedReady={(e: NativeSyntheticEvent<{ listingCount: number }>) => {
        onFeedReady?.(e.nativeEvent.listingCount)
      }}
      onListingTap={(e: NativeSyntheticEvent<{ listing: SellwildListing }>) => {
        const result = onListingTap?.(e.nativeEvent.listing)
        if (__DEV__ && result === true && !consumeListingTaps && !warnedReturnTrue.current) {
          warnedReturnTrue.current = true
          console.warn(
            '[Sellwild] onListingTap returned true, but the return value is ignored ' +
              '(RN events are async). Set consumeListingTaps on <SellwildFeed> to ' +
              'stop the SDK from opening the listing.',
          )
        }
      }}
      onAdImpression={(e: NativeSyntheticEvent<{ zoneId: string }>) => {
        onAdImpression?.(e.nativeEvent.zoneId)
      }}
      onHouseAdImpression={(e: NativeSyntheticEvent<{ zoneId: string }>) => {
        onHouseAdImpression?.(e.nativeEvent.zoneId)
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
