/**
 * Sellwild Core SDK — Runnable Sample
 *
 * How to run:
 *   cd sdk/samples/core
 *   npm install
 *   npx ts-node sample.ts
 *
 * Or compile and run:
 *   npx tsc --esModuleInterop sample.ts && node sample.js
 */

// In a real project after `npm install @sellwild/sdk-core`:
//   import { buildConfig, fetchListings, getAdPlacements, buildPrebidAdUnit,
//            buildGptTagUrl, isGeoBlocked, setUserLocation, currencyToSymbol,
//            eventQueue, clearListingCache } from '@sellwild/sdk-core'
//
// For local development from the monorepo, use a relative path:
import {
  buildConfig,
  buildConfigWithRemote,
  configure,
  fetchRemoteConfig,
  clearRemoteConfigCache,
  fetchListings,
  getAdPlacements,
  buildPrebidAdUnit,
  buildGptTagUrl,
  isGeoBlocked,
  setUserLocation,
  currencyToSymbol,
  eventQueue,
  clearListingCache,
} from '../../core/src/index'

// ─── 1. Build a config ───────────────────────────────────────────────────────

// ─── MODE A: Prebid.js client-side in WebView (default) ──────────────────────
// Each bidder adapter runs client-side inside the WebView.
// Provide appBundleId so Prebid.js declares in-app (ortb2.app) inventory.
const config = buildConfig({
  partnerCode: 'demo',

  // Required: declares in-app inventory for Prebid.js (ortb2.app).
  appBundleId: 'com.mycompany.myapp',
  appStoreUrl: 'https://apps.apple.com/app/idXXXXXXXXX',

  // Optional: Google Ad Manager
  gamTag: '/12345678/demo-mobile',

  // Optional: banner zone IDs
  bannerZid: '98765',
  mobileZids: ['11111', '22222'],

  // Optional: ad refresh
  adRefreshMaxMobile: 5,
  adRefreshInterval: 30000,

  // Optional: Prebid bidder credentials (client-side mode)
  ix: { siteIdM: 'ix-mobile-id', siteIdMB: '', siteIdD: 'ix-desktop-id',
        siteIdDB: '', siteIdD160x600: '', siteIdD300x600: '' },

  debug: true,
})

// ─── MODE B: Prebid Server S2S (optional, solves cookie/IDFA limitations) ─────
// Uncomment to route all Prebid bids server-side through your Prebid Server instance.
// The WebView makes one request; the server fans out to all configured bidders.
// See https://docs.prebid.org/prebid-server/overview/prebid-server-overview.html
//
// const configWithS2S = buildConfig({
//   ...config,
//   prebidServer: {
//     accountId: 'YOUR_ACCOUNT_ID',
//     endpoint: 'https://prebid-server.example.com/openrtb2/auction',
//     // AppNexus hosted: 'https://prebid.adnxs.com/pbs/v1/openrtb2/auction'
//     // Rubicon hosted:  'https://prebid-server.rubiconproject.com/openrtb2/auction'
//     bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
//     timeout: 1500,
//   },
// })

console.log('=== Static Config ===')
console.log('Partner:', config.partnerCode)
console.log('Ad refresh interval:', config.adRefreshInterval, 'ms')
console.log('Max mobile refreshes:', config.adRefreshMaxMobile)
console.log()

// ─── 1b. Remote config from CDN — the first-class path ─────────────────────
// `configure(partnerCode, slug)` fetches every runtime field from
// https://widget.sellwild.com/app/{partnerCode}/{slug}.json and returns a
// fully-built SellwildConfig. Two strings = working SDK.
// Managed via the Sellwild CMS — toggle bidders, adjust refresh, enable
// interstitials, change ad zones, all without an app update.

async function runRemoteConfig() {
  console.log('=== Remote Config (configure) ===')
  const remoteConfig = await configure('weatherbug', 'weatherbug-main', { timeout: 5000 })
  console.log('Partner:', remoteConfig.partnerCode)
  console.log('Ad refresh max:', remoteConfig.adRefreshMax)
  console.log('Ad refresh max mobile:', remoteConfig.adRefreshMaxMobile)
  console.log('Enable interstitial:', remoteConfig.enableInterstitial)
  console.log('Enable fullscreen video:', remoteConfig.enableFullscreenVideo)
  console.log('Interstitials per session:', remoteConfig.interstitialsPerSession)
  console.log('IX disabled:', remoteConfig.ix?.disabled)
  console.log('OpenX disabled:', remoteConfig.openx?.disabled)

  // Clear cache on app foreground to pick up CMS changes
  clearRemoteConfigCache()
  console.log('Remote config cache cleared.')
  console.log()
}

// ─── 2. Fetch listings ───────────────────────────────────────────────────────

async function runListingsFetch() {
  console.log('=== Fetching Listings ===')

  try {
    const response = await fetchListings(config)
    console.log(`Received ${response.listings.length} listings`)

    for (const listing of response.listings.slice(0, 3)) {
      const symbol = currencyToSymbol(listing.currency || 'USD')
      const price = listing.price ? `${symbol}${Number(listing.price).toLocaleString()}` : 'No price'
      console.log(`  [${listing.id}] ${listing.title} — ${price}`)
      if (listing.photos[0]) {
        console.log(`         Photo: ${listing.photos[0].url}`)
      }
    }

    if (response.widgetCacheVersionId) {
      console.log('Cache version:', response.widgetCacheVersionId)
    }
  } catch (err) {
    console.error('Fetch failed:', (err as Error).message)
    console.log('(This is expected if running without network access to the listings URL)')
  }

  console.log()
}

// ─── 3. Ad placement logic ───────────────────────────────────────────────────

function runAdPlacements() {
  console.log('=== Ad Placements (mobile) ===')
  const placements = getAdPlacements(config, /* isMobile */ true)

  for (const p of placements) {
    console.log(`  type=${p.type}  size=${p.size}  zoneId=${p.zoneId ?? '—'}  gamTag=${p.gamTag ?? '—'}`)
  }
  console.log()

  console.log('=== Ad Placements (desktop) ===')
  const desktopPlacements = getAdPlacements(config, /* isMobile */ false)
  for (const p of desktopPlacements) {
    console.log(`  type=${p.type}  size=${p.size}  zoneId=${p.zoneId ?? '—'}`)
  }
  console.log()
}

// ─── 4. Prebid ad unit building ──────────────────────────────────────────────

function runPrebidAdUnit() {
  console.log('=== Prebid Ad Unit ===')
  const placement = { type: 'banner_top' as const, size: '320x50' as const, zoneId: '98765' }
  const unit = buildPrebidAdUnit(config, placement, 'instance-1')

  console.log('Code:', unit.code)
  console.log('Sizes:', JSON.stringify(unit.mediaTypes.banner.sizes))
  console.log('Bidders:')
  for (const bid of unit.bids) {
    console.log(`  ${bid.bidder}:`, JSON.stringify(bid.params))
  }
  console.log()
}

// ─── 5. GPT tag URL building ─────────────────────────────────────────────────

function runGptTagUrl() {
  console.log('=== GPT Tag URL ===')
  const url = buildGptTagUrl(config, '320x50')
  console.log(url)
  console.log()
}

// ─── 6. Geo blocking ─────────────────────────────────────────────────────────

function runGeoBlocking() {
  console.log('=== Geo Blocking ===')

  // Simulate a user from California
  setUserLocation('US', 'CA', 'los angeles', 'NA')

  const configWithGeoBlock = buildConfig({
    ...config,
    adGeoBlock: { countries: '', states: 'CA,NY', cities: '', continents: '' },
  })

  const blocked = isGeoBlocked(configWithGeoBlock)
  console.log('User in CA, block rule for CA,NY → blocked:', blocked)  // true

  setUserLocation('US', 'TX', 'austin', 'NA')
  const notBlocked = isGeoBlocked(configWithGeoBlock)
  console.log('User in TX, block rule for CA,NY → blocked:', notBlocked)  // false
  console.log()
}

// ─── 7. Event queue ──────────────────────────────────────────────────────────

function runEventQueue() {
  console.log('=== Event Queue ===')
  eventQueue.push({ event: 'widget_load', action: 'load', label: 'demo' })
  eventQueue.push({ event: 'ad_impression', action: 'banner_top', label: '98765' })
  console.log('Queued 2 events. UID:', eventQueue.getUid())
  // In a real app, eventQueue.flush() is called automatically after 10 seconds.
  // Call eventQueue.flush() explicitly before app close.
  console.log()
}

// ─── 8. Cache management ─────────────────────────────────────────────────────

function runCacheManagement() {
  console.log('=== Cache Management ===')
  // After a pull-to-refresh, clear the listing cache so the next fetchListings
  // hits the network instead of returning the cached promise.
  clearListingCache()
  console.log('Listing cache cleared.')
  console.log()
}

// ─── Run everything ──────────────────────────────────────────────────────────

async function main() {
  runAdPlacements()
  runPrebidAdUnit()
  runGptTagUrl()
  runGeoBlocking()
  runEventQueue()
  runCacheManagement()

  // Remote config fetch — demonstrates CDN config loading
  await runRemoteConfig()

  // Listings fetch requires network — runs last
  await runListingsFetch()
}

main().catch(console.error)
