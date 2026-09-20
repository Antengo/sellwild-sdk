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
