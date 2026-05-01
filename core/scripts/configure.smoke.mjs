// Smoke test for `configure()` and the listings-URL fallback.
//
// Run with: `node core/scripts/configure.smoke.mjs` from the repo root.
// Requires `core/dist` to exist — run `npm run build` in core first.

import { configure, clearRemoteConfigCache, fetchRemoteConfig, resolveListingsUrl } from '../dist/index.js'

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
    LISTINGS: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
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
    config.listingsUrl === 'https://api.sellwild.com/widget/listings?partner=weatherbug',
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
    '404 → resolveListingsUrl gives deterministic default',
    resolveListingsUrl(config) === 'https://api.sellwild.com/widget/listings?partner=newpartner',
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
    LISTINGS: 'https://api.sellwild.com/widget/listings?partner=weatherbug',
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

globalThis.fetch = origFetch

console.log(`\n${pass} passed, ${fail} failed`)
if (fail > 0) process.exit(1)
