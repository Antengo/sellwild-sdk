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

// Parse a BANNER_SIZES value — `["300x250","320x50"]` or `[[300,250],…]`,
// possibly a JSON string — into {width,height}[]. Mirrors the native
// SellwildAdSizes parser so the RN slot reasons about the same size set the
// auction requests.
function parseSizeList(raw: unknown): Array<{ width: number; height: number }> {
  let arr: unknown = raw
  if (typeof raw === 'string') {
    try { arr = JSON.parse(raw) } catch { arr = [raw] }
  }
  if (!Array.isArray(arr)) return []
  const out: Array<{ width: number; height: number }> = []
  for (const e of arr) {
    if (typeof e === 'string') {
      const [w, h] = e.toLowerCase().split('x').map((s) => Number(s.trim()))
      if (w > 0 && h > 0) out.push({ width: w, height: h })
    } else if (Array.isArray(e) && e.length === 2) {
      const w = Number(e[0]); const h = Number(e[1])
      if (w > 0 && h > 0) out.push({ width: w, height: h })
    }
  }
  return out
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
  onAdResize?: (e: NativeSyntheticEvent<{ width: number; height: number }>) => void
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

  // The widest/tallest size the auction may return for this placement: the
  // primary plus any BANNER_SIZES / BANNER_SIZES_BY_ZONE fallbacks. We reserve
  // this as the slot's baseline so a wider or taller fallback creative — e.g. a
  // 320x50 winning a 300-wide MREC request, where 320 > 300 — never clips
  // before, or without, the onAdResize callback. This also covers the Android
  // prebidOnly path, whose rendering BannerView doesn't surface the winning
  // creative size (so onAdResize can't shrink it back down there).
  const baseline = React.useMemo(() => {
    const remote = (config.remote ?? {}) as Record<string, unknown>
    const byZone = remote['BANNER_SIZES_BY_ZONE']
    const zoned = byZone && typeof byZone === 'object'
      ? (byZone as Record<string, unknown>)[String(zoneId)]
      : undefined
    const sizes = [dim, ...parseSizeList(zoned ?? remote['BANNER_SIZES'])]
    return {
      width: Math.max(...sizes.map((s) => s.width)),
      height: Math.max(...sizes.map((s) => s.height)),
    }
  }, [dim, zoneId, config.remote])

  // The slot starts at the reserved baseline, then tracks whatever the native
  // side actually renders (onAdResize): a multi-size fallback creative, an
  // outstream video, or the capped native template. Where the actual size is
  // reported it shrinks the slot to fit; where it isn't (Android prebidOnly)
  // the baseline reservation prevents a clip.
  const [rendered, setRendered] = React.useState<{ width: number; height: number } | null>(null)
  // Reset to the baseline when the placement identity changes.
  React.useEffect(() => { setRendered(null) }, [size, zoneId])

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

  // Pass only the fields the native banner path actually reads. The rest
  // of SellwildConfig is ignored on the native side. Note: TS core uses
  // `adRefreshInterval` (millis); the native side reads it as
  // `adRefreshIntervalMs`. The bridge translates.
  const nativeConfig = {
    partnerCode: config.partnerCode,
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
    // Local GrowthCode overrides (remote GROWTHCODE_* keys ride `remote`).
    growthCode: config.growthCode,
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
      onAdResize={(e: NativeSyntheticEvent<{ width: number; height: number }>) => {
        const { width, height } = e.nativeEvent ?? { width: 0, height: 0 }
        if (width > 0 && height > 0) setRendered({ width, height })
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
