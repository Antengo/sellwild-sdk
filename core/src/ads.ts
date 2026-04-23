import { SellwildConfig, AdSize, AdPlacement, AdPlacementType } from './types'

// Geo region detection (populated from API response headers in web;
// in mobile apps, populated from device locale or IP-based lookup)
export const userLocation = {
  city: { name: '' },
  state: { code: '' },
  country: { code: '' },
  continent: { code: '' },
}

export function setUserLocation(country: string, state: string, city: string, continent: string): void {
  userLocation.country.code = country.toUpperCase()
  userLocation.state.code = state.toUpperCase()
  userLocation.city.name = city.toLowerCase()
  userLocation.continent.code = continent.toUpperCase()
}

const GDPR_COUNTRIES = new Set([
  'AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU',
  'IE','IT','LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE','GB',
])
const CCPA_STATES = new Set(['CA'])

export function isGdprRegion(): boolean {
  return GDPR_COUNTRIES.has(userLocation.country.code)
}

export function isCcpaRegion(): boolean {
  return CCPA_STATES.has(userLocation.state.code)
}

// Determine which ad placements should be active for a given config
export function getAdPlacements(config: SellwildConfig, isMobile: boolean): AdPlacement[] {
  const placements: AdPlacement[] = []

  if (!config.hideBannerTop && config.bannerZid) {
    placements.push({
      type: 'banner_top',
      size: isMobile ? '320x50' : '728x90',
      zoneId: isMobile ? config.mobileBannerZid || config.bannerZid : config.bannerZid,
    })
  }

  if (!config.hideBannerBottom && config.bottomBannerZid) {
    placements.push({
      type: 'banner_bottom',
      size: isMobile ? '320x50' : '728x90',
      zoneId: config.bottomBannerZid,
    })
  }

  const inlineZids = isMobile ? config.mobileZids : config.displayZids
  for (const zoneId of inlineZids) {
    placements.push({
      type: 'inline',
      size: isMobile ? '300x250' : '300x250',
      zoneId,
    })
  }

  if (config.gamTag) {
    placements.push({
      type: 'banner_top',
      size: isMobile ? '320x50' : '728x90',
      gamTag: config.gamTag,
    })
  }

  return placements
}

// Build a Prebid.js ad unit definition for a given placement
export interface PrebidAdUnit {
  code: string
  mediaTypes: {
    banner: { sizes: [number, number][] }
  }
  bids: Array<{ bidder: string; params: Record<string, unknown> }>
}

function sizeToArray(size: AdSize): [number, number] {
  const [w, h] = size.split('x').map(Number)
  return [w, h]
}

export function buildPrebidAdUnit(
  config: SellwildConfig,
  placement: AdPlacement,
  instanceId: string
): PrebidAdUnit {
  const bids: PrebidAdUnit['bids'] = []
  const isMobile = placement.size === '320x50' || placement.size === '300x250'

  if (config.ix && !config.ix.disabled) {
    bids.push({
      bidder: 'ix',
      params: { siteId: isMobile ? config.ix.siteIdM : config.ix.siteIdD },
    })
  }

  if (config.openx && !config.openx.disabled) {
    bids.push({
      bidder: 'openx',
      params: {
        delDomain: config.openx.delDomain,
        unit: isMobile ? config.openx.unitM : config.openx.unitD,
      },
    })
  }

  if (config.pubmatic && !config.pubmatic.disabled) {
    bids.push({
      bidder: 'pubmatic',
      params: {
        publisherId: config.pubmatic.pubIdM,
        adSlot: isMobile ? config.pubmatic.adSlotM : config.pubmatic.adSlotD,
      },
    })
  }

  if (config.appnexus && !config.appnexus.disabled) {
    bids.push({
      bidder: 'appnexus',
      params: {
        placementId: isMobile ? config.appnexus.placementIdM : config.appnexus.placementIdD,
      },
    })
  }

  if (config.rubicon && !config.rubicon.disabled) {
    bids.push({
      bidder: 'rubicon',
      params: {
        accountId: config.rubicon.accountId,
        siteId: isMobile ? config.rubicon.siteIdM : config.rubicon.siteIdD,
        zoneId: isMobile ? config.rubicon.zoneIdM : config.rubicon.zoneIdD,
      },
    })
  }

  return {
    code: `${config.slug}-${placement.type}-${instanceId}`,
    mediaTypes: {
      banner: { sizes: [sizeToArray(placement.size)] },
    },
    bids,
  }
}

// GPT tag URL builder
export function buildGptTagUrl(config: SellwildConfig, size: AdSize): string {
  const proxy = config.gptProxyUrl || 'https://securepubads.g.doubleclick.net'
  const [w, h] = sizeToArray(size)
  const tag = config.gamTag || ''
  return `${proxy}/gampad/ads?iu=${encodeURIComponent(tag)}&sz=${w}x${h}&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1`
}

// Check if an ad should render based on geo block rules
export function isGeoBlocked(config: SellwildConfig): boolean {
  if (!config.adGeoBlock) return false

  const { countries, states, cities, continents } = config.adGeoBlock

  if (continents && continents.split(',').some(c => c.trim().toLowerCase() === userLocation.continent.code.toLowerCase())) {
    return true
  }
  if (countries && countries.split(',').some(c => c.trim().toLowerCase() === userLocation.country.code.toLowerCase())) {
    return true
  }
  if (states && states.split(',').some(s => s.trim().toLowerCase() === userLocation.state.code.toLowerCase())) {
    return true
  }
  if (cities && cities.split(',').some(c => c.trim().toLowerCase() === userLocation.city.name.toLowerCase())) {
    return true
  }

  return false
}

// Determine effective ad refresh max (mobile-aware)
export function getEffectiveRefreshMax(config: SellwildConfig, isMobile: boolean): number {
  if (isMobile && config.adRefreshMaxMobile !== undefined && config.adRefreshMaxMobile >= 0) {
    return config.adRefreshMaxMobile
  }
  return config.adRefreshMax || 0
}
