// Cases for golden/sdk-timing.vectors.json. Expected values come from
// reference/sdk-timing.mjs (scripts/generate-vectors.mjs).

export const NOW = 1790000000000
export const UID_IN = 't14' // fnv1a32('t14:timing') / 2^32 ≈ 0.0126: sampled at the default 0.1
export const UID_OUT = 'uid-a' // ≈ 0.6360: out at 0.1, in at 0.7

const S0 = Object.freeze({ sessionCount: 0 })
const ctx = (over = {}) => ({
  partnerCode: 'weatherbug',
  client: 'ios',
  clientVersion: '1.8.1',
  appId: 'com.aws.weatherbug',
  appVersion: '6.12.0',
  os: 'iOS 26.1',
  device: 'iPhone16,2',
  uid: UID_IN,
  now: NOW,
  ...over,
})
const c = (name, input, over = {}, stateBefore = S0) => ({ name, input, context: ctx(over), stateBefore })

export function buildTimingCases() {
  return [
    c('timing.config-fetch-sampled-in', { step: 'config.fetch', ms: 412.6 }),
    c('timing.every-step', { step: 'listings.decode', ms: 3 }),
    c('timing.first-listing', { step: 'feed.firstListing', ms: 1820 }),
    c('timing.first-ad-with-zone', { step: 'ad.firstLoad', ms: 2500, zoneId: ' 43 ' }),
    c('timing.sampled-out-at-default', { step: 'listings.fetch', ms: 900 }, { uid: UID_OUT }),
    c('timing.rate-override-in', { step: 'listings.fetch', ms: 900 }, { uid: UID_OUT, timingSampleRate: '0.7' }),
    c('timing.rate-zero', { step: 'listings.fetch', ms: 900 }, { timingSampleRate: 0 }),
    c('timing.rate-invalid-is-default', { step: 'listings.fetch', ms: 900 }, { uid: UID_OUT, timingSampleRate: '70%' }),
    c('timing.kill-switch', { step: 'config.fetch', ms: 1 }, { timingEnabled: 'off' }),
    c('timing.events-off', { step: 'config.fetch', ms: 1 }, { eventsEnabled: false }),
    c('timing.unknown-step', { step: 'config.parse', ms: 1 }),
    c('timing.negative-ms', { step: 'config.fetch', ms: -1 }),
    c('timing.ms-not-a-number', { step: 'config.fetch', ms: '12' }),
    c('timing.ms-over-ten-minutes', { step: 'config.fetch', ms: 600001 }),
    c('timing.session-capped', { step: 'config.fetch', ms: 5 }, {}, { sessionCount: 50 }),
    c('timing.seq-continues', { step: 'config.fetch', ms: 5 }, {}, { sessionCount: 7 }),
    c('timing.context-missing', { step: 'config.fetch', ms: 0 }, { partnerCode: undefined, client: '', clientVersion: null, appId: '  ', os: undefined, device: undefined, appVersion: 3 }),
    c('timing.net-and-cleaning', { step: 'config.fetch', ms: 10.5 }, { net: 'wifi', device: 'iPhone\n16,2' }),
  ]
}

export const TIMING_UNITS = {
  budgetFor: [
    ['config.fetch', null], ['listings.fetch', {}], ['ad.firstLoad', { TIMING_BUDGET_AD_MS: 8000 }],
    ['config.fetch', { TIMING_BUDGET_CONFIG_MS: '1500' }], ['config.fetch', { TIMING_BUDGET_CONFIG_MS: 0 }],
    ['config.fetch', { TIMING_BUDGET_CONFIG_MS: '1.5s' }], ['config.fetch', { TIMING_BUDGET_CONFIG_MS: 2500.9 }],
    ['listings.decode', { TIMING_BUDGET_LISTINGS_MS: 10 }], ['feed.firstListing', null],
  ],
  isSlow: [
    ['config.fetch', 3000, null], ['config.fetch', 3000.5, null], ['listings.fetch', 4001, {}],
    ['ad.firstLoad', 7000, { TIMING_BUDGET_AD_MS: '8000' }], ['listings.decode', 99999, null],
  ],
  timingRate: [null, 0, 1, 0.5, 2, -1, '0.25', '', 'abc', true],
}
