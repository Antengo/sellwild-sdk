// Smoke test for `configure()` and the listings-URL fallback.
//
// Run with: `node core/scripts/configure.smoke.mjs` from the repo root.
// Requires `core/dist` to exist — run `npm run build` in core first.

import { configure, clearRemoteConfigCache, fetchRemoteConfig, resolveListingsUrl, resolveAdStack, parseAdStack } from '../dist/index.js'

let pass = 0
let fail = 0

function check(name, ok, detail) {
  if (ok) {
    pass++
    console.log(`  ok ${name}`)
  } else {
    fail++
    console.error(`  FAIL ${name}`, detail ?? '')
  }
}

function makeFetch(payload, status = 200) {
  const calls = []
  const fn = (url) => {
    calls.push(url)
    if (payload === null) {
      return Promise.resolve(new Response('not found', { status: 404 }))
    }
    return Promise.resolve(new Response(JSON.stringify(payload), { status }))
  }
  fn.calls = calls
  return fn
}

const origFetch = globalThis.fetch

// Test 1 — Successful CDN fetch populates listingsUrl, mobileZids, app identity
{
  clearRemoteConfigCache()
  const mock = makeFetch({
    CODE: 'weatherbug',
    LISTINGS: 'https://cache.sellwild.com/listings-img-data-sm',
    MOBILE_ZID: ['12345', '67890'],
    AD_REFRESH_INTERVAL: 30,
    APP_BUNDLE_ID: 'com.aws.android',
    APP_STORE_URL: 'https://play.google.com/store/apps/details?id=com.aws.android',
  })
  globalThis.fetch = mock

  const config = await configure('weatherbug', 'weatherbug-main')

  check('partnerCode preserved', config.partnerCode === 'weatherbug')
  check('slug preserved', config.slug === 'weatherbug-main')
  check(
    'listingsUrl from CDN',
    config.listingsUrl === 'https://cache.sellwild.com/listings-img-data-sm',
  )
  check(
    'mobileZids from CDN',
    Array.isArray(config.mobileZids) && config.mobileZids.length === 2,
  )
  check('appBundleId from CDN', config.appBundleId === 'com.aws.android')
  check(
    'fetched expected URL',
    mock.calls[0] === 'https://widget.sellwild.com/app/weatherbug/weatherbug-main.json',
    mock.calls[0],
  )
}

// Test 2 — 404 falls back gracefully, listingsUrl resolves deterministically
{
  clearRemoteConfigCache()
  globalThis.fetch = makeFetch(null)
  const config = await configure('newpartner', 'newpartner-main')
  check('404 → partnerCode set', config.partnerCode === 'newpartner')
  check('404 → listingsUrl undefined', config.listingsUrl === undefined)
  check(
    '404 → resolveListingsUrl gives general listings cache default',
    resolveListingsUrl(config) === 'https://cache.sellwild.com/listings-img-data-sm',
  )
}

// Test 3 — overrides win over CDN
{
  clearRemoteConfigCache()
  globalThis.fetch = makeFetch({
    APP_BUNDLE_ID: 'com.cdn.value',
    DEBUG: false,
  })
  const config = await configure('weatherbug', 'weatherbug-main', {
    overrides: { appBundleId: 'com.app.override', debug: true },
  })
  check('override wins over CDN appBundleId', config.appBundleId === 'com.app.override')
  check('override wins over CDN debug', config.debug === true)
}

// Test 4 — cache prevents second fetch
{
  clearRemoteConfigCache()
  const mock = makeFetch({ CODE: 'weatherbug' })
  globalThis.fetch = mock
  await fetchRemoteConfig('weatherbug', 'weatherbug-main')
  await fetchRemoteConfig('weatherbug', 'weatherbug-main')
  check('cache prevents second fetch', mock.calls.length === 1)
}

// Test 5 — config.remote contains raw CDN payload (passthrough for unmapped keys)
{
  clearRemoteConfigCache()
  const raw = {
    CODE: 'weatherbug',
    LISTINGS: 'https://cache.sellwild.com/listings-img-data-sm',
    // Unmapped CMS keys (no entry in KEY_MAP) — must still flow through:
    MEDIANET: { cid: '8CU123ABC' },
    AMX: { tagId: 'amx-tag-1' },
    SOVRN: { tagid: 12345 },
    ONETAG: { pubId: 'abc' },
    YIELDMO: { placementId: 'ym-1' },
  }
  globalThis.fetch = makeFetch(raw)
  const config = await configure('weatherbug', 'weatherbug-main')
  check('remote populated', config.remote && typeof config.remote === 'object')
  check('remote carries unmapped MEDIANET', config.remote?.MEDIANET?.cid === '8CU123ABC')
  check('remote carries unmapped AMX', config.remote?.AMX?.tagId === 'amx-tag-1')
  check('remote carries unmapped SOVRN', config.remote?.SOVRN?.tagid === 12345)
}

// Test 6 — IAB_CATS scalar from CDN is coerced to string[] (regression: $configIabCats.join is not a function)
{
  clearRemoteConfigCache()
  globalThis.fetch = makeFetch({
    CODE: 'weatherbug',
    IAB_CATS: 'IAB15', // CMS ships scalar; SDK type is string[]
  })
  const config = await configure('weatherbug', 'weatherbug-iab-scalar')
  check('iabCats coerced from string to array', Array.isArray(config.iabCats))
  check('iabCats has expected single value', config.iabCats?.length === 1 && config.iabCats[0] === 'IAB15')

  clearRemoteConfigCache()
  globalThis.fetch = makeFetch({
    CODE: 'weatherbug',
    IAB_CATS: 'IAB15, IAB15-10 ,IAB7',
  })
  const config2 = await configure('weatherbug', 'weatherbug-iab-csv')
  check(
    'iabCats coerced from CSV string',
    Array.isArray(config2.iabCats) &&
      config2.iabCats.length === 3 &&
      config2.iabCats[0] === 'IAB15' &&
      config2.iabCats[1] === 'IAB15-10' &&
      config2.iabCats[2] === 'IAB7',
  )
}

// Test 7 — ad-stack parse tolerance
{
  check('parseAdStack BOTH', parseAdStack('BOTH') === 'both')
  check('parseAdStack alias google → gamOnly', parseAdStack('google') === 'gamOnly')
  check('parseAdStack PREBID_ONLY → prebidOnly', parseAdStack('PREBID_ONLY') === 'prebidOnly')
  check('parseAdStack gam-only (hyphen) → gamOnly', parseAdStack('gam-only') === 'gamOnly')
  check('parseAdStack unknown → undefined', parseAdStack('xyz') === undefined)
}

// Test 8 — ad-stack mapping from CDN + resolution precedence
{
  clearRemoteConfigCache()
  globalThis.fetch = makeFetch({
    CODE: 'weatherbug',
    AD_STACK: 'PREBID',
    AD_STACK_BY_ZONE: { '43': 'GAM', '44': 'BOTH' },
  })
  const config = await configure('weatherbug', 'weatherbug-adstack')
  check('AD_STACK mapped to adStack', config.adStack === 'prebidOnly')
  check('AD_STACK_BY_ZONE mapped', config.adStackByZone?.['43'] === 'gamOnly')
  // Global hard-wins over per-zone.
  check('global hard-wins over per-zone', resolveAdStack(config, '43') === 'prebidOnly')
  check('global hard-wins (no zone)', resolveAdStack(config) === 'prebidOnly')
}

// Test 9 — per-zone applies when no global; default both
{
  clearRemoteConfigCache()
  globalThis.fetch = makeFetch({
    CODE: 'weatherbug',
    AD_STACK_BY_ZONE: { '43': 'gamOnly', '99': 'prebidOnly' },
  })
  const config = await configure('weatherbug', 'weatherbug-perzone')
  check('per-zone 43 → gamOnly', resolveAdStack(config, '43') === 'gamOnly')
  check('per-zone 99 → prebidOnly', resolveAdStack(config, 99) === 'prebidOnly')
  check('unlisted zone → both', resolveAdStack(config, '7') === 'both')
  check('no zone, no global → both', resolveAdStack(config) === 'both')
}

// Test 10 — absent keys preserve today's default behavior
{
  clearRemoteConfigCache()
  globalThis.fetch = makeFetch({ CODE: 'weatherbug' })
  const config = await configure('weatherbug', 'weatherbug-default')
  check('no AD_STACK keys → adStack undefined', config.adStack === undefined)
  check('no AD_STACK keys → resolves both', resolveAdStack(config, '43') === 'both')
}

globalThis.fetch = origFetch

console.log(`\n${pass} passed, ${fail} failed`)
if (fail > 0) process.exit(1)
