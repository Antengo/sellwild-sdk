import type { SellwildConfig } from '@sellwild/sdk-core'
import { resolveListingsUrl } from '@sellwild/sdk-core'

const WIDGET_CDN = 'https://widget.sellwild.com'

// buildBannerHtml is dead code pending a delete decision; see ./bannerHtml.
export { buildBannerHtml } from './bannerHtml'

/**
 * `text` as the value of an HTML attribute quoted with `quote`: the parser
 * gives back exactly `text`. `&` goes first, so a value that already holds a
 * character reference (`&amp;`, `&copy `) is not decoded by the page either.
 */
export function escapeAttribute(text: string, quote: '"' | "'"): string {
  const escaped = text.replace(/&/g, '&amp;')
  return quote === '"' ? escaped.replace(/"/g, '&quot;') : escaped.replace(/'/g, '&#39;')
}

/**
 * `value` as a JSON literal inside an inline <script>. The HTML parser ends a
 * script at the first `</script`, even inside a JS string, so every `<` is
 * written as the JSON escape \u003c: JS reads back the same value.
 */
export function scriptJson(value: unknown): string {
  return JSON.stringify(value).replace(/</g, '\\u003c')
}

/**
 * Whether the widget tag can carry `key` as an attribute name. The HTML parser
 * ends a name at whitespace, '/', '=' or '>', so a key holding one would split
 * into other attributes or end the tag, and every attribute after it would be
 * lost; an empty key is no name at all. Anything else is written as it is, as
 * before (a quote or '<' is a parse error, but the parser keeps it in the
 * name). Pure.
 */
export function isAttributeName(key: string): boolean {
  return /^[^\t\n\f\r /=>]+$/.test(key)
}

/**
 * The remote config keys the widget tag leaves out because they cannot be
 * attribute names (isAttributeName). SellwildWidget reports them. Pure.
 */
export function unwritableRemoteKeys(config: SellwildConfig): string[] {
  return config.remote ? Object.keys(config.remote).filter((key) => !isAttributeName(key)) : []
}

// ─────────────────────────────────────────────────────────────────────────────
// Prebid.js WebView pre-configuration
//
// This script runs BEFORE prebid.js loads by enqueuing via pbjs.que.
// It addresses two critical WebView issues:
//
// 1. ortb2.app — Prebid.js running in a native WebView must declare itself as
//    in-app inventory (OpenRTB app object) rather than web (site object).
//    Without this, bid requests look like browser traffic; DSPs that buy app
//    inventory separately will not bid, and app-ads.txt enforcement is bypassed.
//
// 2. userSync iframe filtering — Third-party cookies are blocked in all native
//    WebViews (WKWebView, Android WebView). Iframe-based cookie syncs will
//    always fail silently, wasting network requests and adding latency. Image
//    pixel syncs may still work for some bidders. A longer syncDelay gives the
//    auction time to complete before sync requests compete for bandwidth.
// ─────────────────────────────────────────────────────────────────────────────
export function buildPrebidPreConfigScript(config: SellwildConfig): string {
  const ortb2App: Record<string, unknown> = {
    publisher: { id: config.partnerCode },
  }
  if (config.appBundleId) ortb2App['bundle'] = config.appBundleId
  if (config.appStoreUrl) ortb2App['storeurl'] = config.appStoreUrl

  // GDPR / privacy signals — PBS defaults to gdpr=1 (GDPR applies) and
  // blocks all bidder calls if no consent string is present. The SDK must
  // explicitly declare the user's jurisdiction so the server knows whether
  // to enforce consent. The host app provides gdprApplies and tcString
  // via SellwildConfig; default is gdpr=0 (US traffic, not subject).
  const ortb2Regs: Record<string, unknown> = {
    ext: { gdpr: (config as any).gdprApplies ? 1 : 0 },
  }
  const ortb2User: Record<string, unknown> = {}
  if ((config as any).gdprApplies && (config as any).tcString) {
    ortb2User['ext'] = { consent: (config as any).tcString }
  }

  let s2sConfigBlock = ''
  if (config.prebidServer) {
    const ps = config.prebidServer
    const s2s = {
      accountId: ps.accountId,
      bidders: ps.bidders,
      timeout: ps.timeout ?? 1500,
      adapter: 'prebidServer',
      endpoint: { p1Consent: ps.endpoint, noP1Consent: ps.endpoint },
      ...(ps.syncEndpoint
        ? { syncEndpoint: { p1Consent: ps.syncEndpoint, noP1Consent: ps.syncEndpoint } }
        : {}),
    }
    s2sConfigBlock = `,
        // Route all Prebid bidder calls through Prebid Server (S2S mode).
        // Solves cookie/IDFA limitations — the auction runs server-to-server.
        s2sConfig: ${scriptJson(s2s)}`
  }

  return `
  <script>
    // Prebid.js WebView pre-configuration — runs before prebid.js initialises.
    window.pbjs = window.pbjs || {};
    window.pbjs.que = window.pbjs.que || [];
    window.pbjs.que.push(function() {
      window.pbjs.setConfig({
        // Declare in-app inventory so DSPs bid on app traffic, not web traffic.
        // Include regs.ext.gdpr so PBS knows whether to enforce consent.
        ortb2: {
          app: ${scriptJson(ortb2App)},
          regs: ${scriptJson(ortb2Regs)}${Object.keys(ortb2User).length ? `,
          user: ${scriptJson(ortb2User)}` : ''}
        },
        // Iframe cookie syncs always fail in WebViews — disable them.
        // Image pixel syncs may still work for some bidders.
        userSync: {
          filterSettings: {
            iframe: { bidders: '*', filter: 'exclude' }
          },
          syncDelay: 5000
        }${s2sConfigBlock}${config.debug ? `,
        // debug mode
        debug: true` : ''}
      });
    });
  </script>`
}

// ─────────────────────────────────────────────────────────────────────────────
// Config → element attributes
//
// The sellwild-widget reads configuration from HTML element attributes via
// withCustomizationsFromElement() in src/providers/Customizations/index.ts.
// Attribute names can be in any case (kebab-case, camelCase, CONSTANT_CASE).
// Complex objects are JSON-stringified; arrays are comma-separated.
// ─────────────────────────────────────────────────────────────────────────────
export function configToAttributes(config: SellwildConfig): string {
  const parts: string[] = []

  const add = (name: string, value: unknown) => {
    if (value === undefined || value === null || value === '' || value === false || value === 0) return
    // Escaped, so a quote inside a value (a CMS LINK_TEXT holding an <a
    // href="...">) cannot end the attribute and cut off the rest of the tag.
    if (typeof value === 'object') {
      parts.push(`${name}='${escapeAttribute(JSON.stringify(value), "'")}'`)
    } else {
      parts.push(`${name}="${escapeAttribute(String(value), '"')}"`)
    }
  }

  // Identity / listings
  add('partner-code', config.partnerCode)
  add('listings', resolveListingsUrl(config))

  // Disable remote customization fetch — the widget defaults to fetching
  // https://widget.sellwild.com/{partnerCode}/{slug}.json which (a) doesn't
  // exist for SDK consumers and (b) is unnecessary because the SDK supplies
  // every customization via element attributes already.
  parts.push('customize="false"')

  // Ad system selection — REQUIRED. AdStack.initializeAdStack() switches on
  // theme.adType and silently does nothing if it's unset, meaning Prebid never
  // loads and no auctions ever run. PrebidOnly is the dominant value across
  // production publisher widgets. Override via config.adType if needed.
  add('ad-type', (config as any).adType || 'PrebidOnly')

  // Display
  add('title', config.title)
  add('link-text', config.linkText)
  add('buy-now-text', config.buyNowText)
  add('title-color', config.titleColor)
  add('title-size', config.titleSize)
  add('link-color', config.linkColor)
  add('link-size', config.linkSize)
  add('font-size', config.fontSize)
  add('font-family', config.fontFamily)
  add('font-color', config.fontColor)
  add('price-color', config.priceColor)
  add('price-font-color', config.priceFontColor)
  add('margin-bottom', config.marginBottom)
  add('card-width', config.cardWidth)
  add('card-height', config.cardHeight)
  add('colors', config.colors?.join(','))
  add('watermark', config.watermark || undefined)
  add('watermark-title', config.watermarkTitle)
  add('overlay-title', config.overlayTitle || undefined)
  add('css', config.css)

  // Ads – display
  add('gam-tag', config.gamTag)
  add('gam-tag-desc', config.gamTagDesc)
  add('banner-zid', config.bannerZid)
  add('bottom-banner-zid', config.bottomBannerZid)
  add('mobile-banner-zid', config.mobileBannerZid)
  // Filter empties before joining — the widget's parser splits on ',' and
  // does not strip empty strings, so a stray comma yields [""] not [].
  add('mobile-zid', config.mobileZids?.filter(Boolean).join(','))
  add('display-zid', config.displayZids?.filter(Boolean).join(','))
  add('skyscraper-zid', config.skyscraperZid)
  add('hide-banner-top', config.hideBannerTop || undefined)
  add('hide-banner-bottom', config.hideBannerBottom || undefined)
  add('gpt-proxy-url', config.gptProxyUrl)
  add('disable-gpt', config.disableGpt || undefined)
  add('ad-disable-display', config.adDisableDisplay || undefined)
  add('safe-frame', config.safeFrame || undefined)

  // Ads – refresh
  add('ad-refresh-max', config.adRefreshMax)
  add('ad-refresh-max-mobile', config.adRefreshMaxMobile)
  add('ad-refresh-interval', config.adRefreshInterval)
  add('max-failed-auctions', config.maxFailedAuctions)
  add('prebid-src', config.prebidSrc)
  add('prebid-defer', config.prebidDefer)
  add('floor-multiplier', config.floorMultiplier !== 1 ? config.floorMultiplier : undefined)

  // Ads – geo
  add('ad-geo-block', config.adGeoBlock)
  add('ad-geo-block-refresh', config.adGeoBlockRefresh)

  // Ads – compliance
  add('gpp-enabled', config.gppEnabled || undefined)
  add('tcf-version', config.tcfVersion)
  add('consent-management', config.consentManagement)
  add('schain-sid', config.schainSid)
  add('s2s-config', config.s2sConfig)
  add('iab-cats', Array.isArray(config.iabCats) ? config.iabCats.join(',') : config.iabCats)

  // Third-party (typed fields with defaults — kept emitted explicitly for
  // backwards compatibility with static buildConfig() callers)
  add('boltive', config.boltive || undefined)
  add('boltive-client-id', config.boltiveClientId)
  add('lotame', config.lotame || undefined)
  add('growthcode', config.growthcode)
  add('bh-tag', config.bhTag)

  // Mobile ad controls
  add('enable-interstitial', config.enableInterstitial || undefined)
  add('enable-fullscreen-video', config.enableFullscreenVideo || undefined)
  add('interstitials-per-session', config.interstitialsPerSession)
  add('video-takeovers-per-session', config.videoTakeoversPerSession)

  // Debug
  add('debug', config.debug || undefined)
  add('membership-type', config.membershipType)

  // ─── Remote passthrough ────────────────────────────────────────────────────
  // Forward the raw CDN payload verbatim. The widget's attribute parser is
  // case-insensitive (kebab-case / camelCase / CONSTANT_CASE all work) and
  // accepts unknown keys, so every CMS-defined bidder, waterfall partner, or
  // ad-network setting flows through to the WebView without an SDK release.
  //
  // Skip keys that we already emitted via typed fields above to avoid
  // double-emission. Identity fields (CODE, SLUG, NAME, LISTINGS) are handled
  // by the typed block; everything else (bidders, third-party, etc.) lands
  // here as the canonical CONSTANT_CASE attribute.
  const emittedFromTyped = new Set<string>([
    'CODE', 'SLUG', 'NAME', 'LISTINGS',
    'TITLE', 'LINK_TEXT', 'BUY_NOW_TEXT', 'TITLE_COLOR', 'LINK_COLOR',
    'FONT_FAMILY', 'FONT_URL', 'FONT_COLOR', 'PRICE_COLOR', 'PRICE_FONT_COLOR',
    'MARGIN_BOTTOM', 'CARD_WIDTH', 'OVERLAY_TITLE', 'COLORS', 'CSS',
    'WATERMARK', 'WATERMARK_TITLE',
    'BANNER_ZID', 'BOTTOM_BANNER_ZID', 'MOBILE_BANNER_ZID', 'MOBILE_ZID',
    'DISPLAY_ZID', 'HIDE_BANNER_TOP', 'HIDE_BANNER_BOTTOM', 'GAM',
    'DISABLE_GPT', 'AD_UNITS', 'SAFE_FRAME', 'AD_DISABLE_DISPLAY',
    'AD_REFRESH_MAX', 'AD_REFRESH_MAX_MOBILE', 'AD_REFRESH_INTERVAL',
    'MAX_FAILED_AUCTIONS', 'PREBID_DEFER', 'PREBID_SRC',
    'AD_GEO_BLOCK', 'AD_GEO_BLOCK_REFRESH',
    'GPP_ENABLED', 'TCF_VERSION', 'CONSENT_MANAGEMENT', 'SCHAIN_SID',
    'S2S_CONFIG', 'IAB_CATS',
    'ENABLE_INTERSTITIAL', 'ENABLE_FULLSCREEN_VIDEO',
    'INTERSTITIALS_PER_SESSION', 'VIDEO_TAKEOVERS_PER_SESSION',
    'BOLTIVE', 'BOLTIVE_CLIENT_ID', 'LOTAME', 'GROWTHCODE', 'BH_TAG',
  ])
  if (config.remote) {
    for (const [key, value] of Object.entries(config.remote)) {
      // A key that cannot be an attribute name would break the tag; it is
      // left out, and SellwildWidget reports it (unwritableRemoteKeys).
      if (emittedFromTyped.has(key) || !isAttributeName(key)) continue
      add(key, value)
    }
  }

  return parts.join('\n    ')
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget HTML builder
//
// The widget JS URL can be:
//   - A publisher-specific bundle: https://widget.sellwild.com/{CODE}/{SLUG}.js
//     (config already baked in at build time; element attributes are optional)
//   - The generic bundle: https://widget.sellwild.com/partner.js
//     (reads all config from element attributes — SDK default)
//
// Pass widgetJsUrl in config to override the default generic bundle.
// ─────────────────────────────────────────────────────────────────────────────
export function buildWidgetHtml(config: SellwildConfig & { widgetJsUrl?: string }): string {
  // partner.js is the canonical generic widget bundle. It loads its own Prebid
  // build internally (from cache.sellwild.com), so the SDK MUST NOT inject a
  // separate prebid <script> tag — doing so causes a double-load and breaks
  // header bidding initialization order.
  const widgetSrc = config.widgetJsUrl ?? `${WIDGET_CDN}/partner.js`
  const attrs = configToAttributes(config)

  const prebidPreConfig = buildPrebidPreConfigScript(config)

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: 100%; background: transparent; overflow-x: hidden; }
  </style>
  ${prebidPreConfig}
</head>
<body>
  <sellwild-widget
    ${attrs}
  ></sellwild-widget>

  <script>
    (function() {
      function send(type, payload) {
        try {
          window.ReactNativeWebView.postMessage(JSON.stringify(Object.assign({ type: type }, payload || {})));
        } catch(e) {
          // The bridge is the page's only way out, so this cannot be reported.
          // Count it where a debugger can read it.
          window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1;
        }
      }

      // partner/index.tsx calls window.open() on listing tap — intercept ALL
      // calls. Listings link to external sites (eBay, Amazon, dealer sites, etc.)
      // so we can't filter by domain. The widget only uses window.open for listings.
      var _open = window.open;
      window.open = function(url) {
        if (url) {
          send('LISTING_CLICK', { url: url });
          return null;
        }
        return _open.apply(window, arguments);
      };

      document.addEventListener('DOMContentLoaded', function() {
        setTimeout(function() { send('WIDGET_LOADED'); }, 600);
      });

      window.addEventListener('error', function(e) {
        send('ERROR', { message: e.message || 'Widget load error' });
      });
    })();
  </script>

  <script async src="${escapeAttribute(widgetSrc, '"')}"></script>
</body>
</html>`
}
