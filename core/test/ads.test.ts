import { afterEach, describe, expect, it } from 'vitest'
import {
  buildGptTagUrl,
  buildPrebidAdUnit,
  getAdPlacements,
  getEffectiveRefreshMax,
  isCcpaRegion,
  isCcpaRegionFor,
  isGdprRegion,
  isGdprRegionFor,
  isGeoBlocked,
  isGeoBlockedFor,
  parseAdSize,
  setUserLocation,
  userLocation,
  type UserLocation,
} from '../src/ads'
import type { AdPlacement, AdSize, SellwildConfig } from '../src/types'
import { appConfig, sellwildConfig, type AppConfigPayload } from './factories'
import { expectValid } from './support/factory-checks'
import { countLogFailureCalls, takeFailureEvents, takeRecordedFailures } from './support/failures'

// A typed config merged from the minimal CMS fixture plus CMS overrides (checked
// against the app-config contract), then local typed overrides.
function adConfig(cms: Partial<AppConfigPayload> = {}, local: Partial<SellwildConfig> = {}): SellwildConfig {
  const raw = appConfig(cms, 'minimal')
  expectValid('app-config', raw)
  return sellwildConfig(local, raw)
}

const at = (country: string, state = '', city = '', continent = ''): UserLocation => ({
  country: { code: country },
  state: { code: state },
  city: { name: city },
  continent: { code: continent },
})

afterEach(() => {
  setUserLocation('', '', '', '')
})

describe('user location, GDPR and CCPA', () => {
  it('stores codes upper case and the city lower case', () => {
    setUserLocation('fr', 'idf', 'Paris', 'eu')
    expect(userLocation).toEqual(at('FR', 'IDF', 'paris', 'EU'))
  })

  it('reads GDPR and CCPA from a given location', () => {
    expect(isGdprRegionFor(at('DE'))).toBe(true)
    expect(isGdprRegionFor(at('GB'))).toBe(true)
    expect(isGdprRegionFor(at('US'))).toBe(false)
    expect(isCcpaRegionFor(at('US', 'CA'))).toBe(true)
    expect(isCcpaRegionFor(at('US', 'NY'))).toBe(false)
  })

  it('reads GDPR and CCPA from the global location', () => {
    expect([isGdprRegion(), isCcpaRegion()]).toEqual([false, false])
    setUserLocation('it', 'ca', '', 'eu')
    expect([isGdprRegion(), isCcpaRegion()]).toEqual([true, true])
  })
})

describe('getAdPlacements', () => {
  const zoned = { BANNER_ZID: 43, BOTTOM_BANNER_ZID: '44', MOBILE_ZID: ['m1', 'm2'], DISPLAY_ZID: ['d1'] }

  it('places the top and bottom banners and the inline zones for mobile', () => {
    expect(getAdPlacements(adConfig({ ...zoned, MOBILE_BANNER_ZID: 45 }), true)).toEqual<AdPlacement[]>([
      { type: 'banner_top', size: '320x50', zoneId: 45 },
      { type: 'banner_bottom', size: '320x50', zoneId: '44' },
      { type: 'inline', size: '300x250', zoneId: 'm1' },
      { type: 'inline', size: '300x250', zoneId: 'm2' },
    ])
    expect(getAdPlacements(adConfig(zoned), true)[0]).toEqual({ type: 'banner_top', size: '320x50', zoneId: 43 })
  })

  it('places them for desktop with the display zones', () => {
    expect(getAdPlacements(adConfig({ ...zoned, MOBILE_BANNER_ZID: 45 }), false)).toEqual<AdPlacement[]>([
      { type: 'banner_top', size: '728x90', zoneId: 43 },
      { type: 'banner_bottom', size: '728x90', zoneId: '44' },
      { type: 'inline', size: '300x250', zoneId: 'd1' },
    ])
  })

  it('skips hidden banners and banners without a zone', () => {
    expect(getAdPlacements(adConfig({ ...zoned, HIDE_BANNER_TOP: true, HIDE_BANNER_BOTTOM: true }), true).map((p) => p.type)).toEqual(['inline', 'inline'])
    expect(getAdPlacements(adConfig(), false)).toEqual([])
  })

  it('adds a GAM top banner when a GAM tag is set', () => {
    expect(getAdPlacements(adConfig({ GAM: '/1234/app' }), true)).toEqual([{ type: 'banner_top', size: '320x50', gamTag: '/1234/app' }])
    expect(getAdPlacements(adConfig({ GAM: '/1234/app' }), false)).toEqual([{ type: 'banner_top', size: '728x90', gamTag: '/1234/app' }])
  })
})

describe('parseAdSize', () => {
  it.each([
    ['320x50', [320, 50]], ['300x250', [300, 250]], ['1x1', [1, 1]], [' 728 x 90 ', [728, 90]], ['300x250.5', [300, 250.5]],
  ])('reads %j as %j', (size, dims) => {
    expect(parseAdSize(size)).toEqual(dims)
  })

  it.each(['300X250', '0x0', '320x', 'x50', '1x2x3', 'axb', '', 320, null, undefined])('gives null for %j', (size) => {
    expect(parseAdSize(size)).toBeNull()
  })
})

describe('buildPrebidAdUnit', () => {
  const bidders = {
    IX: { siteIdM: 'ixM', siteIdD: 'ixD' },
    OPENX: { delDomain: 'sellwild-d.openx.net', unitM: 'oxM', unitD: 'oxD' },
    PUBMATIC: { pubIdM: 'pm', adSlotM: 'pmM', adSlotD: 'pmD' },
    APPNEXUS: { placementIdM: 11, placementIdD: 12 },
    RUBICON: { accountId: 1, siteIdM: 2, zoneIdM: 3, siteIdD: 4, zoneIdD: 5 },
  }
  const top = (size: AdSize): AdPlacement => ({ type: 'banner_top', size })

  it('bids every enabled network with its mobile ids for a mobile size', () => {
    const config = adConfig({ ...bidders, SLUG: 'fixture-app' })
    expect(buildPrebidAdUnit(config, top('320x50'), 'i1')).toEqual({
      code: 'fixture-app-banner_top-i1',
      mediaTypes: { banner: { sizes: [[320, 50]] } },
      bids: [
        { bidder: 'ix', params: { siteId: 'ixM' } },
        { bidder: 'openx', params: { delDomain: 'sellwild-d.openx.net', unit: 'oxM' } },
        { bidder: 'pubmatic', params: { publisherId: 'pm', adSlot: 'pmM' } },
        { bidder: 'appnexus', params: { placementId: 11 } },
        { bidder: 'rubicon', params: { accountId: 1, siteId: 2, zoneId: 3 } },
      ],
    })
    expect(buildPrebidAdUnit(config, top('300x250'), 'i2').bids[0]).toEqual({ bidder: 'ix', params: { siteId: 'ixM' } })
  })

  it('uses the desktop ids for a desktop size', () => {
    const unit = buildPrebidAdUnit(adConfig(bidders), top('728x90'), 'i3')
    expect(unit.mediaTypes.banner.sizes).toEqual([[728, 90]])
    expect(unit.bids.map((b) => b.params)).toEqual([
      { siteId: 'ixD' },
      { delDomain: 'sellwild-d.openx.net', unit: 'oxD' },
      { publisherId: 'pm', adSlot: 'pmD' },
      { placementId: 12 },
      { accountId: 1, siteId: 4, zoneId: 5 },
    ])
  })

  it('leaves out disabled and missing networks', () => {
    const disabled = {
      IX: { ...bidders.IX, disabled: true },
      OPENX: { ...bidders.OPENX, disabled: true },
      PUBMATIC: { ...bidders.PUBMATIC, disabled: true },
      APPNEXUS: { ...bidders.APPNEXUS, disabled: true },
      RUBICON: { ...bidders.RUBICON, disabled: true },
    }
    expect(buildPrebidAdUnit(adConfig(disabled), top('320x50'), 'i4').bids).toEqual([])
    expect(buildPrebidAdUnit(adConfig(), top('320x50'), 'i5').bids).toEqual([])
    expect(takeFailureEvents()).toEqual([])
  })

  it('reports a size that is not WxH once, and reads it as it always has', async () => {
    let unit: ReturnType<typeof buildPrebidAdUnit> | undefined
    const calls = await countLogFailureCalls(() => {
      unit = buildPrebidAdUnit(adConfig(), top('300X250' as AdSize), 'i6')
    })

    expect(calls).toEqual({ 'ad.size.invalid': 1 })
    expect(unit!.mediaTypes.banner.sizes).toEqual([[Number.NaN, undefined]])
    expect(takeRecordedFailures()).toMatchObject([
      { event: { action: 'ad.size.invalid', label: 'banner', attributes: { severity: 'warn', msg: "ad size '300X250' is not WxH" } } },
    ])
  })
})

describe('buildGptTagUrl', () => {
  it('builds the VAST tag URL on the default GPT host, or the proxy', () => {
    expect(buildGptTagUrl(adConfig({ GAM: '/1234/app video' }), '300x250')).toBe(
      'https://securepubads.g.doubleclick.net/gampad/ads?iu=%2F1234%2Fapp%20video&sz=300x250&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1',
    )
    expect(buildGptTagUrl(adConfig({}, { gptProxyUrl: 'https://gpt.proxy.example' }), '320x50')).toBe(
      'https://gpt.proxy.example/gampad/ads?iu=&sz=320x50&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1',
    )
  })

  it('reports a malformed size once and still builds the URL it always built', async () => {
    const calls = await countLogFailureCalls(() => {
      expect(buildGptTagUrl(adConfig(), '0x0' as AdSize)).toContain('&sz=0x0&')
    })

    expect(calls).toEqual({ 'ad.size.invalid': 1 })
    expect(takeFailureEvents()).toMatchObject([{ action: 'ad.size.invalid', attributes: { msg: "ad size '0x0' is not WxH" } }])
  })

  it('reports a size that is not text once, then throws the TypeError it always threw', async () => {
    const calls = await countLogFailureCalls(() => {
      expect(() => buildGptTagUrl(adConfig(), undefined as never)).toThrow(TypeError)
      expect(() => buildGptTagUrl(adConfig(), null as never)).toThrow(TypeError)
    })

    expect(calls).toEqual({ 'ad.size.invalid': 2 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual(['ad size is undefined, not WxH text', 'ad size is null, not WxH text'])
  })
})

describe('isGeoBlockedFor and isGeoBlocked', () => {
  const blocked = (block: Record<string, string>, loc: UserLocation) => isGeoBlockedFor(adConfig({ AD_GEO_BLOCK: block }), loc)

  it('does not block without geo block rules', () => {
    expect(isGeoBlockedFor(adConfig(), at('FR'))).toBe(false)
  })

  it('blocks on a continent, country, state or city in the comma lists, any case and spacing', () => {
    expect(blocked({ continents: 'na, EU' }, at('', '', '', 'EU'))).toBe(true)
    expect(blocked({ countries: 'FR, de' }, at('DE'))).toBe(true)
    expect(blocked({ states: 'ca ,NY' }, at('US', 'NY'))).toBe(true)
    expect(blocked({ cities: 'Paris, Lyon' }, at('FR', '', 'lyon'))).toBe(true)
  })

  // The lists and the location are compared in lower case, on both sides.
  it.each([
    ['continent', 'continents', 'eu', at('', '', '', 'EU'), at('', '', '', 'eu')],
    ['country', 'countries', 'fr', at('FR'), at('fr')],
    ['state', 'states', 'ny', at('US', 'NY'), at('US', 'ny')],
    ['city', 'cities', 'paris', at('FR', '', 'PARIS'), at('FR', '', 'paris')],
  ])('matches a %s whatever the case of the list or the location', (_name, key, value, upper, lower) => {
    expect(blocked({ [key]: value }, upper)).toBe(true)
    expect(blocked({ [key]: value }, lower)).toBe(true)
    expect(blocked({ [key]: value.toUpperCase() }, lower)).toBe(true)
  })

  it('does not block when nothing matches, or the lists are empty', () => {
    expect(blocked({ continents: 'AS', countries: 'FR', states: 'CA', cities: 'paris' }, at('US', 'NY', 'albany', 'NA'))).toBe(false)
    expect(blocked({ continents: '', countries: '', states: '', cities: '' }, at('US'))).toBe(false)
  })

  it('reads the global location', () => {
    const config = adConfig({ AD_GEO_BLOCK: { countries: 'FR' } })
    expect(isGeoBlocked(config)).toBe(false)
    setUserLocation('fr', '', '', '')
    expect(isGeoBlocked(config)).toBe(true)
  })
})

describe('getEffectiveRefreshMax', () => {
  it('uses the mobile max on mobile when it is set and not negative, else the shared max', () => {
    expect(getEffectiveRefreshMax(adConfig({ AD_REFRESH_MAX: 5, AD_REFRESH_MAX_MOBILE: 2 }), true)).toBe(2)
    expect(getEffectiveRefreshMax(adConfig({ AD_REFRESH_MAX: 5, AD_REFRESH_MAX_MOBILE: 0 }), true)).toBe(0)
    expect(getEffectiveRefreshMax(adConfig({ AD_REFRESH_MAX: 5, AD_REFRESH_MAX_MOBILE: -1 }), true)).toBe(5)
    expect(getEffectiveRefreshMax(adConfig({ AD_REFRESH_MAX: 5 }, { adRefreshMaxMobile: undefined }), true)).toBe(5)
    expect(getEffectiveRefreshMax(adConfig({ AD_REFRESH_MAX: 5, AD_REFRESH_MAX_MOBILE: 2 }), false)).toBe(5)
    expect(getEffectiveRefreshMax(adConfig({}, { adRefreshMax: undefined as never }), false)).toBe(0)
  })
})
