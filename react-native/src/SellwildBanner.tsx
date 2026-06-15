import React from 'react'
import { Platform, requireNativeComponent, UIManager, ViewStyle, View, Text, StyleSheet, NativeSyntheticEvent } from 'react-native'
import { resolveAdStack, type SellwildConfig, type AdSize } from '@sellwild/sdk-core'

// Standard IAB mobile ad sizes — used to lock the host View dimensions.
// The actual ad size is also propagated to native as the `size` prop label.
const AD_DIMENSIONS: Record<AdSize, { width: number; height: number }> = {
  '300x250': { width: 300, height: 250 },
  '320x50': { width: 320, height: 50 },
  '728x90': { width: 728, height: 90 },
  '160x600': { width: 160, height: 600 },
  '300x600': { width: 300, height: 600 },
  '1x1': { width: 1, height: 1 },
}

// ─── Native component bridge ─────────────────────────────────────────────────
//
// As of 1.3.0 the React Native banner is backed by a real native ad view —
// `com.sellwild.sdk.SellwildAdView` on Android (Prebid Mobile + AdManagerAdView)
// and `SellwildAdView` on iOS (Prebid Mobile + AdManagerBannerView). There is
// no WebView in the ad path on either platform.
//
// The Android bridge lives in `react-native/android` and is autolinked via
// the `@sellwild/react-native-sdk` package.

const NATIVE_NAME = 'SellwildBannerView'

interface NativeBannerProps {
  config: object
  size: string
  zoneId: string
  /**
   * Resolved ad stack ('both' | 'gamOnly' | 'prebidOnly'). Computed in JS from
   * the config so RN is deterministic; native treats it as the highest-priority
   * override. The raw `remote` payload still flows through `config` for
   * everything else (bidders, GAM tag, etc.).
   */
  adStack: string
  style?: ViewStyle
  onAdLoaded?: (e: NativeSyntheticEvent<{}>) => void
  onAdImpression?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onAdClicked?: (e: NativeSyntheticEvent<{}>) => void
  onAdFailed?: (e: NativeSyntheticEvent<{ message: string }>) => void
}

const NativeBanner = (() => {
  // requireNativeComponent crashes loudly if the view manager isn't
  // registered. Probe first so we can render a friendly fallback on
  // platforms where the bridge isn't in this build yet.
  const config = UIManager.getViewManagerConfig?.(NATIVE_NAME)
  if (!config) {
    return null
  }
  return requireNativeComponent<NativeBannerProps>(NATIVE_NAME)
})()

// ─── Public component ────────────────────────────────────────────────────────

export interface SellwildBannerProps {
  config: SellwildConfig
  size: AdSize
  zoneId: number | string
  style?: ViewStyle
  onImpression?: () => void
  onClick?: () => void
  onError?: (error: Error) => void
}

export function SellwildBanner({
  config,
  size,
  zoneId,
  style,
  onImpression,
  onClick,
  onError,
}: SellwildBannerProps) {
  const dim = AD_DIMENSIONS[size]
  const containerStyle: ViewStyle = { width: dim.width, height: dim.height }

  if (!NativeBanner) {
    // Native module not registered. Most common cause: iOS bridge not yet
    // wired (1.3.0 ships the Android bridge first; iOS lands in 1.3.x).
    // Render a visible placeholder in dev builds so the gap is obvious;
    // production builds get a transparent slot of the right dimensions.
    return (
      <View style={[containerStyle, style, __DEV__ ? styles.devPlaceholder : undefined]}>
        {__DEV__ ? (
          <Text style={styles.devText}>
            Sellwild native banner not available on {Platform.OS} (yet)
          </Text>
        ) : null}
      </View>
    )
  }

  // Pass only the fields the native banner path actually reads. The rest
  // of SellwildConfig is ignored on the native side. Note: TS core uses
  // `adRefreshInterval` (millis); the native side reads it as
  // `adRefreshIntervalMs`. The bridge translates.
  const nativeConfig = {
    partnerCode: config.partnerCode,
    appBundleId: config.appBundleId,
    appStoreUrl: config.appStoreUrl,
    gamTag: config.gamTag,
    debug: config.debug,
    adRefreshMax: config.adRefreshMax,
    adRefreshMaxMobile: config.adRefreshMaxMobile,
    adRefreshIntervalMs: config.adRefreshInterval,
    prebidServer: config.prebidServer,
    remote: config.remote,
  }

  return (
    <NativeBanner
      style={[containerStyle, style]}
      config={nativeConfig}
      size={size}
      zoneId={String(zoneId)}
      adStack={resolveAdStack(config, zoneId)}
      onAdLoaded={() => {
        // No-op event hook today; surfaced for future fill metrics.
      }}
      onAdImpression={() => onImpression?.()}
      onAdClicked={() => onClick?.()}
      onAdFailed={(e: NativeSyntheticEvent<{ message: string }>) => {
        const msg = e.nativeEvent?.message ?? 'Ad failed'
        onError?.(new Error(msg))
      }}
    />
  )
}

const styles = StyleSheet.create({
  devPlaceholder: {
    backgroundColor: '#FEE2E2',
    borderWidth: 1,
    borderColor: '#FCA5A5',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 4,
  },
  devText: {
    color: '#991B1B',
    fontSize: 11,
    textAlign: 'center',
  },
})
