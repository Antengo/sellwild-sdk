import type { SellwildConfig } from '@sellwild/sdk-core'
import { resolveAppIdentity } from './appIdentity'

/**
 * Build the native config payload the auction/ad path reads, from a core
 * SellwildConfig. This is the single source of truth for the fields the native
 * banner path + `prewarm` consume — keep `<SellwildBanner>` and `prewarm()` in
 * sync by both going through here.
 *
 * Notes:
 *  - App identity is resolved per-platform (iOS vs Android) from `config.remote`.
 *  - TS core uses `adRefreshInterval` (millis); the native side reads it as
 *    `adRefreshIntervalMs`. The bridge translates.
 *  - The raw CDN payload rides on `remote` for the auction passthrough.
 */
export function toNativeConfig(config: SellwildConfig): Record<string, unknown> {
  const { appBundleId, appStoreUrl } = resolveAppIdentity(config)
  return {
    partnerCode: config.partnerCode,
    appBundleId,
    appStoreUrl,
    geo: config.geo,
    gamTag: config.gamTag,
    debug: config.debug,
    pbsDebug: config.pbsDebug,
    adRefreshMax: config.adRefreshMax,
    adRefreshMaxMobile: config.adRefreshMaxMobile,
    adRefreshIntervalMs: config.adRefreshInterval,
    prebidServer: config.prebidServer,
    growthCode: config.growthCode,
    localizedListings: config.localizedListings,
    remote: config.remote,
  }
}

/**
 * A zone id as the native feed bridges read it: text. Both read these fields
 * as strings (Android ReadableMap.getString threw for a number; iOS `as?
 * String` dropped one). Text is sent trimmed; a number is sent as its decimal
 * text. Core's unset default 0, and text that is empty or "0" once trimmed,
 * is left out (undefined: the bridge drops the key), as in 1.8.1. So the iOS
 * feed now uses a non-zero numeric zone id that it dropped before this
 * change, and gets no key at all for an unset one.
 */
export function nativeZoneId(zid: unknown): string | undefined {
  let text: string | undefined
  if (typeof zid === 'string') text = zid.trim()
  else if (typeof zid === 'number' && Number.isFinite(zid)) text = String(zid)
  return text === undefined || text === '' || text === '0' ? undefined : text
}

/** A zone id list as text (nativeZoneId), unset entries left out. Anything else is sent as it is. */
export function nativeZoneIds(zids: unknown): unknown {
  if (!Array.isArray(zids)) return zids
  return zids.map(nativeZoneId).filter((zid): zid is string => zid !== undefined)
}

/**
 * The native config payload <SellwildFeed> sends: the fields the native feed
 * reads plus the raw CDN payload under `remote`. The native bridge re-runs
 * the CDN decoder against `remote` to populate feed-specific fields (COL1
 * schedule, bgColor, mobileZids, mobileBannerZid, listingsUrl), so every
 * field need not be mirrored as a typed property here.
 *
 * The key count matters: the iOS feed bridge decides whether to re-apply a
 * config by NSDictionary.hash, which is the key count (a recorded defect in
 * react-native/ios/SellwildFeedViewManager.swift). The keys are the ones the
 * feed sent before, but an undefined value reaches native as no key, and a
 * zone id of 0 is now undefined (nativeZoneId). So for core's default config
 * the iOS feed gets up to 3 fewer keys (bannerZid, bottomBannerZid,
 * mobileBannerZid) than before this change, and a zone id that goes from 0
 * to set adds a key, so the feed re-applies and uses it. Do not add or drop
 * other keys.
 */
export function toNativeFeedConfig(config: SellwildConfig): Record<string, unknown> {
  // App identity is resolved per-platform here (iOS vs Android) from the raw
  // CDN payload on `config.remote`; both native bridges read these fields.
  const { appBundleId, appStoreUrl } = resolveAppIdentity(config)
  return {
    partnerCode: config.partnerCode,
    slug: config.slug,
    appBundleId,
    appStoreUrl,
    geo: config.geo,
    gamTag: config.gamTag,
    debug: config.debug,
    pbsDebug: config.pbsDebug,
    adRefreshMax: config.adRefreshMax,
    adRefreshMaxMobile: config.adRefreshMaxMobile,
    // TS core uses `adRefreshInterval` (ms); the native side reads it as
    // `adRefreshIntervalMs`.
    adRefreshIntervalMs: config.adRefreshInterval,
    prebidServer: config.prebidServer,
    // Local localized-listings overrides (remote LOCALIZED_LISTINGS rides `remote`).
    localizedListings: config.localizedListings,
    // Local GrowthCode overrides (remote GROWTHCODE_* rides `remote`) — parity
    // with SellwildBanner so the feed's native auctions honor local overrides too.
    growthCode: config.growthCode,
    remote: config.remote,
    listingsUrl: config.listingsUrl,
    priceColor: config.priceColor,
    // Zone ids as text (nativeZoneId): a number here crashed the Android feed.
    bannerZid: nativeZoneId(config.bannerZid),
    bottomBannerZid: nativeZoneId(config.bottomBannerZid),
    mobileBannerZid: nativeZoneId(config.mobileBannerZid),
    mobileZids: nativeZoneIds(config.mobileZids),
  }
}
