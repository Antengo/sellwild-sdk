import React from 'react'
import { Platform, StyleProp, ViewStyle, View, Text, StyleSheet, NativeSyntheticEvent } from 'react-native'
import { resolveAdStack, type SellwildConfig, type AdSize } from '@sellwild/sdk-core'
import { adDimensions, bannerBaseline, resizedSlot, type SlotSize } from './bannerSizing'
import { logFailure } from './failures'
import { toNativeConfig } from './nativeConfig'
import { nativeViewOrNull, useMissingNativeViewReport } from './nativeViews'

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
  style?: StyleProp<ViewStyle>
  onAdLoaded?: (e: NativeSyntheticEvent<{}>) => void
  onAdImpression?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onHouseAdImpression?: (e: NativeSyntheticEvent<{ zoneId: string }>) => void
  onAdClicked?: (e: NativeSyntheticEvent<{}>) => void
  onAdFailed?: (e: NativeSyntheticEvent<{ message: string }>) => void
  onAdResize?: (e: NativeSyntheticEvent<{ width: number; height: number }>) => void
}

// Probed once, when this module loads. null renders the fallback slot below.
const NativeBanner = nativeViewOrNull<NativeBannerProps>(NATIVE_NAME)

// ─── Public component ────────────────────────────────────────────────────────

export interface SellwildBannerProps {
  config: SellwildConfig
  size: AdSize
  zoneId: number | string
  style?: ViewStyle
  onImpression?: () => void
  /**
   * Fired when a house ad backfilled an empty slot (a no-fill). NOT a paid
   * impression — track it separately. See the `MOBILE_HOUSE_AD_*` config keys.
   */
  onHouseImpression?: (zoneId: string) => void
  onClick?: () => void
  onError?: (error: Error) => void
}

export function SellwildBanner({
  config,
  size,
  zoneId,
  style,
  onImpression,
  onHouseImpression,
  onClick,
  onError,
}: SellwildBannerProps) {
  // null for a label that is not an AdSize (JS callers are not type-checked).
  // It used to throw a TypeError from the render; the slot now holds the
  // remote fallback sizes, or 0x0, and native gets the label as before.
  const dim = adDimensions(size)

  // The widest/tallest size the auction may return for this placement: the
  // primary plus any BANNER_SIZES / BANNER_SIZES_BY_ZONE fallbacks. We reserve
  // this as the slot's baseline so a wider or taller fallback creative — e.g. a
  // 320x50 winning a 300-wide MREC request, where 320 > 300 — never clips
  // before, or without, the onAdResize callback. This also covers the Android
  // prebidOnly path, whose rendering BannerView doesn't surface the winning
  // creative size (so onAdResize can't shrink it back down there).
  const baseline = React.useMemo(
    () => bannerBaseline(dim, config.remote, zoneId),
    [dim, zoneId, config.remote],
  )

  // The slot starts at the reserved baseline, then tracks whatever the native
  // side actually renders (onAdResize): a multi-size fallback creative, an
  // outstream video, or the capped native template. Where the actual size is
  // reported it shrinks the slot to fit; where it isn't (Android prebidOnly)
  // the baseline reservation prevents a clip.
  const [rendered, setRendered] = React.useState<SlotSize | null>(null)
  // Reset to the baseline when the placement identity changes.
  React.useEffect(() => { setRendered(null) }, [size, zoneId])

  // A label that is not an AdSize is reported here, once per placement. The
  // native bridges (react-native/ios, react-native/android) report only an
  // AdSize they have no native size for (bridge.props.invalid, '1x1' today),
  // so a bad size is logged once (test/nativeGlue.test.ts).
  React.useEffect(() => {
    if (dim) return
    logFailure({
      code: 'ad.size.invalid',
      component: 'banner',
      severity: 'warn',
      message: `size ${String(size)} is not an AdSize`,
      zoneId: String(zoneId),
    })
  }, [dim, size, zoneId])

  useMissingNativeViewReport(NATIVE_NAME, 'banner', !NativeBanner)

  const containerStyle: ViewStyle = {
    width: rendered?.width ?? baseline.width,
    height: rendered?.height ?? baseline.height,
  }

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

  // The fields the native banner path reads. Built via the shared helper so
  // <SellwildBanner> and prewarm() stay in sync (single source of truth).
  const nativeConfig = toNativeConfig(config)

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
      onHouseAdImpression={(e: NativeSyntheticEvent<{ zoneId: string }>) => onHouseImpression?.(e.nativeEvent?.zoneId)}
      onAdClicked={() => onClick?.()}
      onAdFailed={(e: NativeSyntheticEvent<{ message: string }>) => {
        const msg = e.nativeEvent?.message ?? 'Ad failed'
        onError?.(new Error(msg))
      }}
      onAdResize={(e: NativeSyntheticEvent<{ width: number; height: number }>) => {
        const next = resizedSlot(e.nativeEvent)
        if (next) setRendered(next)
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
