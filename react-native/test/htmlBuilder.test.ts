import { describe, expect, it } from 'vitest'
import { buildConfig, type SellwildConfig } from '@sellwild/sdk-core'
import { buildBannerHtml as bannerModuleBuild } from '../src/bannerHtml'
import {
  buildBannerHtml,
  buildPrebidPreConfigScript,
  buildWidgetHtml,
  configToAttributes,
  escapeAttribute,
  isAttributeName,
  unwritableRemoteKeys,
} from '../src/htmlBuilder'
import { appConfig, bridgeMessage, sellwildConfig } from './factories'
import { expectValid } from './support/schemas'
import { decodeCharacterReferences, parseStartTag } from './support/html-tag'
import { runWidgetPage } from './support/widget-page'

function widgetTag(html: string) {
  return parseStartTag(html, 'sellwild-widget')
}

/** A Map as a plain object (the test lib is ES2018: no Object.fromEntries). */
function plain(map: Map<string, string>): Record<string, string> {
  const out: Record<string, string> = {}
  map.forEach((value, key) => {
    out[key] = value
  })
  return out
}

/** The attributes configToAttributes gives `config`, as the widget element reads them. */
function attributesOf(config: SellwildConfig): Map<string, string> {
  const tag = parseStartTag(`<sellwild-widget ${configToAttributes(config)}>`, 'sellwild-widget')
  expect(tag.end).toBeGreaterThan(0)
  return tag.attributes
}

// A partner with no remote config: core's defaults only.
const base = (): SellwildConfig => buildConfig({ partnerCode: 'fixture' })

describe('escapeAttribute', () => {
  const cases: Array<[string, '"' | "'", string]> = [
    ['plain', '"', 'plain'],
    ['say "hi"', '"', 'say &quot;hi&quot;'],
    ["it's", '"', "it's"],
    ["it's", "'", 'it&#39;s'],
    ['say "hi"', "'", 'say "hi"'],
    ['a &amp; b', '"', 'a &amp;amp; b'],
    ['&quot;', "'", '&amp;quot;'],
    ['<b>&</b>', '"', '<b>&amp;</b>'],
  ]

  it.each(cases)('%s in %s quotes', (text, quote, escaped) => {
    expect(escapeAttribute(text, quote)).toBe(escaped)
    // What the HTML parser gives back is the text itself.
    expect(decodeCharacterReferences(escaped)).toBe(text)
  })
})

describe('buildWidgetHtml: attribute values reach the widget as they are', () => {
  it('keeps a CMS value with double quotes inside its attribute (LINK_TEXT of web-passthrough-keys)', () => {
    const remote = appConfig({}, 'web-passthrough-keys')
    expectValid('app-config', remote)
    const config = sellwildConfig({}, remote)
    expect(config.linkText).toBe('<a href="https://sellwild.com?p=fixture">Visit</a>')

    const html = buildWidgetHtml(config)
    const tag = widgetTag(html)

    expect(tag.attributes.get('link-text')).toBe(config.linkText)
    // The tag ends where the SDK closed it, so every later attribute is there.
    expect(html.slice(tag.end)).toMatch(/^<\/sellwild-widget>/)
    expect(tag.attributes.get('ad-type')).toBe('PrebidOnly')
    // The last attribute, from the passthrough block (HTML lower-cases names).
    expect(tag.attributes.get('membership_type')).toBe('69')
    expect(JSON.parse(tag.attributes.get('ix')!)).toEqual(remote.IX)
  })

  const tricky = ['say "hi"', "it's", 'a &amp; b', 'a &copy b', '<b>bold</b>', 'two\nlines']

  it.each(tricky)('round-trips %j in a double-quoted value and inside a JSON value', (value) => {
    const remote = appConfig({ FIXTURE_OBJECT: { text: value } })
    expectValid('app-config', remote)
    const attributes = attributesOf(sellwildConfig({ title: value }, remote))

    expect(attributes.get('title')).toBe(value)
    expect(JSON.parse(attributes.get('fixture_object')!)).toEqual({ text: value })
  })

  it('round-trips every passthrough attribute of the real weatherbug config', () => {
    const remote = appConfig()
    const config = sellwildConfig({}, remote)
    const html = buildWidgetHtml(config)
    const tag = widgetTag(html)
    const written = configToAttributes(config).split('\n').map((line) => line.trim().split('=')[0])

    expect(html.slice(tag.end)).toMatch(/^<\/sellwild-widget>/)
    expect(tag.attributes.get('partner-code')).toBe('weatherbug')
    // Every remote key forwarded under its own name reads back as it was sent.
    const forwarded = Object.keys(remote).filter((key) => written.includes(key))
    expect(forwarded.length).toBeGreaterThan(10)
    for (const key of forwarded) {
      const value = remote[key]
      expect(tag.attributes.get(key.toLowerCase()), key).toBe(typeof value === 'object' ? JSON.stringify(value) : String(value))
    }
    // The S2S_CONFIG JS literal (quotes, newlines) arrives whole.
    expect(tag.attributes.get('s2s-config')).toBe(remote.S2S_CONFIG)
  })
})

describe('configToAttributes: typed fields', () => {
  it('emits identity, customize=false, the ad type and the non-empty defaults', () => {
    expect(plain(attributesOf(base()))).toEqual({
      'partner-code': 'fixture',
      listings: 'https://cache.sellwild.com/listings-img-data-sm',
      customize: 'false',
      'ad-type': 'PrebidOnly',
      'link-text': 'View all',
      'buy-now-text': 'Buy now',
      'title-color': '#000000',
      'title-size': '16',
      'link-color': '#0066cc',
      'link-size': '14',
      'font-size': '13',
      'font-color': '#ffffff',
      'price-color': '#333333',
      'price-font-color': '#ffffff',
      'margin-bottom': '10',
      'card-width': '300px',
      'card-height': '250px',
      colors: '#333333',
      'watermark-title': 'Powered%20by%20Sellwild',
      'ad-refresh-interval': '30000',
      'max-failed-auctions': '3',
    })
  })

  // Each override adds (or changes) exactly these attributes over base().
  const cases: Array<[string, Partial<SellwildConfig> & Record<string, unknown>, Record<string, string>]> = [
    ['title', { title: 'Deals' }, { title: 'Deals' }],
    ['font family', { fontFamily: 'Roboto' }, { 'font-family': 'Roboto' }],
    ['css', { css: '.x{}' }, { css: '.x{}' }],
    ['overlay title', { overlayTitle: true }, { 'overlay-title': 'true' }],
    ['watermark', { watermark: true }, { watermark: 'true' }],
    ['colors, joined', { colors: ['#295baa', '#ffffff'] }, { colors: '#295baa,#ffffff' }],
    ['GAM tag', { gamTag: '/21824729475/app', gamTagDesc: 'app' }, { 'gam-tag': '/21824729475/app', 'gam-tag-desc': 'app' }],
    ['zone ids', { bannerZid: 43, bottomBannerZid: '44', mobileBannerZid: 45, skyscraperZid: 46 }, {
      'banner-zid': '43', 'bottom-banner-zid': '44', 'mobile-banner-zid': '45', 'skyscraper-zid': '46',
    }],
    ['mobile and display zones, empties dropped', { mobileZids: ['a', '', 'b'], displayZids: [7] }, { 'mobile-zid': 'a,b', 'display-zid': '7' }],
    ['banner flags', { hideBannerTop: true, hideBannerBottom: true, disableGpt: true, adDisableDisplay: true, safeFrame: true }, {
      'hide-banner-top': 'true', 'hide-banner-bottom': 'true', 'disable-gpt': 'true', 'ad-disable-display': 'true', 'safe-frame': 'true',
    }],
    ['GPT proxy', { gptProxyUrl: 'https://gpt.sellwild.com' }, { 'gpt-proxy-url': 'https://gpt.sellwild.com' }],
    ['refresh', { adRefreshMax: 5, adRefreshMaxMobile: 3, maxFailedAuctions: 4 }, {
      'ad-refresh-max': '5', 'ad-refresh-max-mobile': '3', 'max-failed-auctions': '4',
    }],
    ['prebid', { prebidSrc: 'https://cache.sellwild.com/prebid.js', prebidDefer: 1 }, {
      'prebid-src': 'https://cache.sellwild.com/prebid.js', 'prebid-defer': '1',
    }],
    ['floor multiplier other than 1', { floorMultiplier: 1.5 }, { 'floor-multiplier': '1.5' }],
    ['geo blocks, as JSON', { adGeoBlock: { countries: 'FR' } as SellwildConfig['adGeoBlock'], adGeoBlockRefresh: { countries: 'DE' } as SellwildConfig['adGeoBlock'] }, {
      'ad-geo-block': '{"countries":"FR"}', 'ad-geo-block-refresh': '{"countries":"DE"}',
    }],
    ['compliance', { gppEnabled: true, tcfVersion: 2, consentManagement: '({gdpr: {}})', schainSid: 'sid', s2sConfig: '[{}]' }, {
      'gpp-enabled': 'true', 'tcf-version': '2', 'consent-management': '({gdpr: {}})', 'schain-sid': 'sid', 's2s-config': '[{}]',
    }],
    ['IAB categories, a list', { iabCats: ['IAB1', 'IAB2'] }, { 'iab-cats': 'IAB1,IAB2' }],
    ['IAB categories, a scalar (IAB_CATS drift)', { iabCats: 'IAB3' as unknown as string[] }, { 'iab-cats': 'IAB3' }],
    ['third parties', { boltive: true, boltiveClientId: 'b', lotame: true, growthcode: 'g', bhTag: 'bh' }, {
      boltive: 'true', 'boltive-client-id': 'b', lotame: 'true', growthcode: 'g', 'bh-tag': 'bh',
    }],
    ['mobile ad controls', { enableInterstitial: true, enableFullscreenVideo: true, interstitialsPerSession: 2, videoTakeoversPerSession: 1 }, {
      'enable-interstitial': 'true', 'enable-fullscreen-video': 'true', 'interstitials-per-session': '2', 'video-takeovers-per-session': '1',
    }],
    ['debug and membership', { debug: true, membershipType: '69' }, { debug: 'true', 'membership-type': '69' }],
    ['ad type override', { adType: 'GamOnly' }, { 'ad-type': 'GamOnly' }],
    ['listings url', { listingsUrl: 'https://cache.sellwild.com/listings-sm' }, { listings: 'https://cache.sellwild.com/listings-sm' }],
  ]

  it.each(cases)('%s', (_name, overrides, added) => {
    const before = plain(attributesOf(base()))
    const after = plain(attributesOf({ ...base(), ...overrides } as SellwildConfig))
    expect(after).toEqual({ ...before, ...added })
  })

  // Empty, false and 0 values are left out, as are lists without entries.
  const omitted: Array<[string, Partial<SellwildConfig>, string]> = [
    ['an empty title', { title: '' }, 'title'],
    ['overlay title false', { overlayTitle: false }, 'overlay-title'],
    ['zone id 0', { bannerZid: 0 }, 'banner-zid'],
    ['a floor multiplier of 1', { floorMultiplier: 1 }, 'floor-multiplier'],
    ['no colors', { colors: undefined as unknown as string[] }, 'colors'],
    ['an empty colors list', { colors: [] }, 'colors'],
    ['no mobile zones', { mobileZids: undefined as unknown as string[] }, 'mobile-zid'],
    ['only empty mobile zones', { mobileZids: ['', ''] }, 'mobile-zid'],
    ['no display zones', { displayZids: undefined as unknown as string[] }, 'display-zid'],
    ['a null css', { css: null as unknown as string }, 'css'],
  ]

  it.each(omitted)('leaves out %s', (_name, overrides, attribute) => {
    expect(attributesOf({ ...base(), ...overrides } as SellwildConfig).has(attribute)).toBe(false)
  })
})

describe('configToAttributes: the remote passthrough', () => {
  it('forwards every remote key the typed block does not emit, and skips the ones it does', () => {
    const remote = appConfig({}, 'web-passthrough-keys')
    const config = sellwildConfig({}, remote)
    const attributes = attributesOf(config)
    // Names as written (HTML parsing lower-cases them), one attribute a line.
    const written = configToAttributes(config).split('\n').map((line) => line.trim().split('=')[0])

    for (const key of ['LAYOUT', 'basename', 'MOBILE_ZID_IOS', 'MOBILE_ZID_ANDROID', 'BIDDERS', 'IX', 'MEMBERSHIP_TYPE']) {
      expect(written, key).toContain(key)
    }
    expect(JSON.parse(attributes.get('bidders')!)).toEqual(remote.BIDDERS)
    // Typed keys are emitted once, by the typed block, under their kebab name.
    for (const key of ['CODE', 'SLUG', 'NAME', 'TITLE', 'LINK_TEXT', 'COLORS', 'CSS', 'MOBILE_ZID', 'AD_GEO_BLOCK', 'CONSENT_MANAGEMENT']) {
      expect(written, key).not.toContain(key)
    }
    expect(written.filter((name) => name === 'title')).toEqual(['title'])
    // Empty values are left out here too.
    for (const key of ['APSTAG', 'PREBID_DEFER', 'AD_GEO_BLOCK_REFRESH', 'GROWTHCODE', 'AD_UNITS']) {
      expect(written, key).not.toContain(key)
    }
  })

  // app-config.schema.json allows any key (additionalProperties, no
  // propertyNames), and the passthrough writes each key as an attribute name.
  // Whitespace, '/', '=' or '>' in one split it into other attributes or end
  // the tag, and every attribute after it is lost (A9: fixed).
  const breakingKeys = ['NEW KEY', 'AD/UNIT', 'A=B', 'X>Y']

  it.each(breakingKeys)('leaves out remote key %j, so the tag keeps every other attribute', (key) => {
    const remote = appConfig({ [key]: 'value', ZZ_LAST: 'kept' })
    expectValid('app-config', remote)
    const html = buildWidgetHtml(sellwildConfig({}, remote))
    const tag = widgetTag(html)

    // The tag ends where the SDK closed it, and the key after the bad one is there.
    expect(html.slice(tag.end)).toMatch(/^<\/sellwild-widget>/)
    expect(tag.attributes.get('zz_last')).toBe('kept')
    // No attribute holds the value under a piece of the key.
    const pieces = key.toLowerCase().split(/[\s/=>]+/)
    for (const piece of pieces) expect(tag.attributes.has(piece), piece).toBe(false)
    expect(Array.from(tag.attributes.values())).not.toContain('value')
  })

  it('forwards any other remote key as it is, even one the HTML parser frowns on', () => {
    // A quote or '<' in a name is a parse error, but the parser keeps it in
    // the name and the tag is intact, so these are written as before.
    const remote = appConfig({ '1PLUSX': 'a', 'data-x': 'b', 'ns:attr.v': 'c', 'QUOTE"KEY': 'd', 'A<B': 'e', ZZ_LAST: 'kept' })
    expectValid('app-config', remote)
    const attributes = attributesOf(sellwildConfig({}, remote))
    expect(['1plusx', 'data-x', 'ns:attr.v', 'quote"key', 'a<b', 'zz_last'].map((name) => attributes.get(name))).toEqual(['a', 'b', 'c', 'd', 'e', 'kept'])
  })

  it.each([
    ['MEMBERSHIP_TYPE', true],
    ['basename', true],
    ['1PLUSX', true],
    ['QUOTE"KEY', true],
    ['A<B', true],
    ['', false],
    ['NEW KEY', false],
    ['TAB\tKEY', false],
    ['LINE\nKEY', false],
    ['FEED\fKEY', false],
    ['CR\rKEY', false],
    ['AD/UNIT', false],
    ['A=B', false],
    ['X>Y', false],
  ])('isAttributeName(%j) is %s', (key, ok) => {
    expect(isAttributeName(key)).toBe(ok)
  })

  it('unwritableRemoteKeys lists the keys it leaves out, in order', () => {
    const remote = appConfig({ 'NEW KEY': 'a', GOOD_KEY: 'b', '': 'c', 'X>Y': 'd' })
    expectValid('app-config', remote)
    expect(unwritableRemoteKeys(sellwildConfig({}, remote))).toEqual(['NEW KEY', '', 'X>Y'])
    expect(unwritableRemoteKeys(sellwildConfig({}, appConfig()))).toEqual([])
    // No remote config at all.
    expect(unwritableRemoteKeys(base())).toEqual([])
  })

  it('does not forward FONT_URL or AD_UNITS: a known defect, recorded, not changed here (A9)', () => {
    // Both keys are listed as emitted by the typed block, but no typed
    // attribute emits them, so the widget never gets them. iOS
    // SellwildWidgetView and Android SellwildAdView skip them the same way.
    const remote = appConfig({ FONT_URL: 'https://fonts.example/roboto.css', AD_UNITS: '[{"code":"x"}]' })
    expectValid('app-config', remote)
    const config = sellwildConfig({}, remote)
    expect(config.fontUrl).toBe('https://fonts.example/roboto.css')
    expect(config.adUnits).toBe('[{"code":"x"}]')

    const attributes = attributesOf(config)

    for (const name of ['font-url', 'font_url', 'ad-units', 'ad_units']) expect(attributes.has(name), name).toBe(false)
  })
})

// The pre-config script, run against a fake window. Returns what it hands
// pbjs.setConfig once Prebid drains its queue. The script ends where the HTML
// parser ends it: at the first '</script' (any case) followed by whitespace,
// '/' or '>'.
function prebidConfigOf(config: SellwildConfig): Record<string, any> {
  const script = /<script>([\s\S]*?)<\/script[\t\n\f\r />]/i.exec(buildPrebidPreConfigScript(config))![1]
  const window: { pbjs?: { que: Array<() => void>; setConfig?: (c: unknown) => void } } = {}
  new Function('window', script)(window)
  const calls: unknown[] = []
  window.pbjs!.setConfig = (c) => calls.push(c)
  for (const fn of window.pbjs!.que) fn()
  expect(calls).toHaveLength(1)
  return calls[0] as Record<string, any>
}

describe('buildPrebidPreConfigScript', () => {
  it('declares in-app inventory, gdpr 0 and the WebView user sync by default', () => {
    expect(prebidConfigOf(base())).toEqual({
      ortb2: { app: { publisher: { id: 'fixture' } }, regs: { ext: { gdpr: 0 } } },
      userSync: { filterSettings: { iframe: { bidders: '*', filter: 'exclude' } }, syncDelay: 5000 },
    })
  })

  it('adds the app bundle and store URL when the config has them', () => {
    const config = sellwildConfig()
    expect(prebidConfigOf(config).ortb2.app).toEqual({
      publisher: { id: 'weatherbug' },
      bundle: config.appBundleId,
      storeurl: config.appStoreUrl,
    })
    expect(config.appBundleId).toBeTruthy()
  })

  it('declares gdpr 1 when it applies, with the consent string only when there is one', () => {
    expect(prebidConfigOf({ ...base(), gdprApplies: true }).ortb2).toEqual({
      app: { publisher: { id: 'fixture' } },
      regs: { ext: { gdpr: 1 } },
    })
    expect(prebidConfigOf({ ...base(), gdprApplies: true, tcString: 'CP-tc' }).ortb2.user).toEqual({ ext: { consent: 'CP-tc' } })
    // A consent string without gdpr is not sent.
    expect(prebidConfigOf({ ...base(), tcString: 'CP-tc' }).ortb2).not.toHaveProperty('user')
  })

  it('routes bidders through Prebid Server when the config has one', () => {
    const endpoint = 'https://prebid.sellwild.com/openrtb2/auction'
    const s2s = prebidConfigOf({ ...base(), prebidServer: { accountId: 'weatherbug', bidders: ['ix'], endpoint } } as SellwildConfig).s2sConfig
    expect(s2s).toEqual({
      accountId: 'weatherbug',
      bidders: ['ix'],
      timeout: 1500,
      adapter: 'prebidServer',
      endpoint: { p1Consent: endpoint, noP1Consent: endpoint },
    })

    const sync = 'https://prebid.sellwild.com/cookie_sync'
    const withSync = prebidConfigOf({
      ...base(),
      prebidServer: { accountId: 'weatherbug', bidders: ['ix'], endpoint, syncEndpoint: sync, timeout: 900 },
    } as SellwildConfig).s2sConfig
    expect(withSync).toMatchObject({ timeout: 900, syncEndpoint: { p1Consent: sync, noP1Consent: sync } })
  })

  // The HTML parser ends a <script> at the first '</script', wherever it is,
  // so a host or CMS value that holds one must not end the pre-config early.
  it('keeps a value holding </script> inside the script, as the value (A9)', () => {
    const storeUrl = 'https://apps.example/app</script><script>window.injected=1</script>'
    const tcString = 'CP</SCRIPT>tc'
    const endpoint = 'https://pbs.example/auction</script>'
    const config = {
      ...base(),
      appStoreUrl: storeUrl,
      gdprApplies: true,
      tcString,
      prebidServer: { accountId: 'acct</script>', bidders: ['ix'], endpoint },
    } as SellwildConfig

    // prebidConfigOf splits the script where the HTML parser would.
    const pbjs = prebidConfigOf(config)

    expect(pbjs.ortb2.app.storeurl).toBe(storeUrl)
    expect(pbjs.ortb2.user).toEqual({ ext: { consent: tcString } })
    expect(pbjs.s2sConfig).toMatchObject({ accountId: 'acct</script>', endpoint: { p1Consent: endpoint } })
    expect(buildPrebidPreConfigScript(config).match(/<\/script/gi)).toHaveLength(1)
  })

  it('turns Prebid debug on with the SDK debug flag', () => {
    expect(prebidConfigOf({ ...base(), debug: true }).debug).toBe(true)
    expect(prebidConfigOf(base())).not.toHaveProperty('debug')
  })
})

describe('buildWidgetHtml: the page', () => {
  const scriptSrc = (html: string) => parseStartTag(html.slice(html.lastIndexOf('<script async')), 'script').attributes.get('src')

  it('loads the generic partner.js bundle by default, or the configured bundle, escaped', () => {
    expect(scriptSrc(buildWidgetHtml(base()))).toBe('https://widget.sellwild.com/partner.js')
    const custom = 'https://widget.sellwild.com/weatherbug/weatherbug.js?v=2&t=1'
    const html = buildWidgetHtml({ ...base(), widgetJsUrl: custom })
    expect(html).toContain('weatherbug.js?v=2&amp;t=1')
    expect(scriptSrc(html)).toBe(custom)
  })

  it.each([
    // Left as it is, the quote ends the src early...
    ['a double quote', 'https://widget.sellwild.com/partner.js?label="beta"'],
    // ...and the reference is decoded to a quote.
    ['a character reference', 'https://widget.sellwild.com/partner.js?q=&quot;'],
  ])('keeps a configured bundle URL with %s as it is', (_name, url) => {
    expect(scriptSrc(buildWidgetHtml({ ...base(), widgetJsUrl: url }))).toBe(url)
  })

  it('posts the bridge messages the contract names', () => {
    const page = runWidgetPage(buildWidgetHtml(base()))
    page.openListing('https://sellwild.com/listing/105140231')
    page.loadDom()
    page.scriptError('Script error.')

    expect(page.posted.map((data) => JSON.parse(data))).toEqual([
      bridgeMessage('LISTING_CLICK'),
      bridgeMessage('WIDGET_LOADED'),
      bridgeMessage('ERROR', { message: 'Script error.' }),
    ])
  })

  it('leaves window.open to the page for a call without a URL', () => {
    const page = runWidgetPage(buildWidgetHtml(base()))
    page.openListing('')
    expect(page.posted).toEqual([])
  })

  it('counts the messages it could not post when the page has no bridge, instead of throwing', () => {
    const page = runWidgetPage(buildWidgetHtml(base()), { bridge: false })

    expect(() => {
      page.loadDom()
      page.scriptError('Script error.')
    }).not.toThrow()

    expect(page.posted).toEqual([])
    expect(page.window.__sellwildBridgeFailures).toBe(2)
  })
})

describe('buildBannerHtml', () => {
  it('is still exported from htmlBuilder (dead code, moved to bannerHtml pending a delete decision)', () => {
    expect(buildBannerHtml).toBe(bannerModuleBuild)
  })
})
