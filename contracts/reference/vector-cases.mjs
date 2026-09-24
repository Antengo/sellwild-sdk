// Inputs for golden/log-failure.vectors.json. Expected values are never written
// here: scripts/generate-vectors.mjs runs each case through the reference.
//
// Each case: { name, input, context, stateBefore }. `context.uid` and
// `context.now` are the uid and clock handed to decideFailure.

export const NOW = 1790000000000
export const UID = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11' // fnv1a32(uid+":failures")/2^32 ≈ 0.2295
export const UID_HIGH = 'uid-d' // ≈ 0.5188
export const UID_VERY_HIGH = 'uid-f' // ≈ 0.8016
export const UID_HASH = 985483424 // fnv1a32(UID + ':failures')

const S0 = Object.freeze({ sessionCount: 0, keys: [] })

const ctx = (over = {}) => ({
  partnerCode: 'weatherbug',
  client: 'ios',
  clientVersion: '1.7.7',
  uid: UID,
  now: NOW,
  ...over,
})

const inp = (over = {}) => ({ code: 'listings.fetch.http', component: 'listings', ...over })

const K503 = 'listings.fetch.http|listings||HTTP 503'
const entry = (key, lastEmitAt, suppressed = 0, emits = 1) => ({ key, lastEmitAt, suppressed, emits })
const state = (sessionCount, keys = []) => ({ sessionCount, keys })
const fill = (n, at = NOW - 120000) =>
  Array.from({ length: n }, (_, i) => entry(`config.fetch.http|remoteConfig||k${String(i).padStart(2, '0')}`, at + i))

const rep = (s, n) => s.repeat(n)

function basic() {
  return [
    {
      name: 'basic.first-failure-flushes',
      input: inp({ message: 'HTTP 503', httpStatus: 503, url: 'https://cache.sellwild.com/listings-img-data-sm?v=2', zoneId: '43' }),
      context: ctx(),
      stateBefore: S0,
    },
    {
      name: 'basic.second-failure-batches',
      input: inp({ message: 'HTTP 503' }),
      context: ctx(),
      stateBefore: state(1, [entry('config.fetch.timeout|remoteConfig||', NOW - 5000)]),
    },
    { name: 'basic.minimal-input', input: { code: 'config.fetch.network', component: 'remoteConfig' }, context: ctx(), stateBefore: S0 },
    { name: 'basic.empty-input', input: {}, context: ctx(), stateBefore: S0 },
    { name: 'basic.state-omitted-fields-default', input: inp(), context: ctx({ client: 'android', clientVersion: '1.7.7' }), stateBefore: S0 },
  ]
}

function sanitize() {
  const m = (name, message, extra = {}) => ({ name, input: inp({ message, ...extra }), context: ctx(), stateBefore: S0 })
  return [
    m('sanitize.email', 'login failed for jane.doe@example.com'),
    m('sanitize.email-multiple-plus-tags', 'to a+b@x.io, cc C.D_E%F@sub.example.co.uk; done'),
    m('sanitize.email-with-digits-local-part', 'user 12345678@x.com unknown'),
    m('sanitize.uuid-lower', 'listing 2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11 missing'),
    m('sanitize.uuid-upper', 'idfa=8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11'),
    m('sanitize.digits-6-masked', 'order 123456 failed'),
    m('sanitize.digits-5-kept', 'zip 90210 and code 12345'),
    m('sanitize.digits-long-run-and-embedded', 'phone 5551234567 ref abc1234567xyz'),
    m('sanitize.digits-dashed-phone-kept', 'call 555-123-4567'),
    m('sanitize.url-to-host', 'GET https://cache.sellwild.com/listings-img-data-sm?pubId=234000&q=couch failed'),
    m('sanitize.url-userinfo-port-case', 'fetch HTTPS://user:secret@Widget.Sellwild.COM:8443/app/x.json'),
    m('sanitize.url-protocol-relative', 'script //widget.sellwild.com/partner.js did not load'),
    m('sanitize.url-without-host', 'cannot read file:///Users/jane/app/config.json'),
    m('sanitize.url-ip-literal', 'connect http://10.0.0.12:8080/health refused'),
    m('sanitize.url-ipv6-literal', 'connect http://[2001:db8::1]:443/ refused'),
    m('sanitize.url-in-parentheses', 'blocked (https://x.example.com/a/b?c=d) by CSP'),
    m('sanitize.url-scheme-only', 'bad url http:// given'),
    m('sanitize.ipv4-bare', 'ECONNREFUSED 192.168.1.20:443'),
    m('sanitize.control-chars', 'a\u0000b\u001bc\u007fd\u0085e\tf'),
    m('sanitize.whitespace-collapse', '  first\n\n  second \r\n third\t\t '),
    m('sanitize.unicode-spaces', 'a\u00a0b\u2003c\u3000d\ufeffe\u2028f'),
    m('sanitize.non-ascii-kept', 'Échec du chargement — réessayer 🙂'),
    m('sanitize.quotes-and-backslash-kept', 'Unexpected token "<" in JSON at C:\\path'),
    m('sanitize.email-inside-url-query', 'redirect https://a.example.com/cb?email=jane@example.com ok'),
    m('sanitize.blank-message-omitted', ' \n\t '),
    {
      name: 'sanitize.message-and-error-joined',
      input: inp({ message: 'listings request failed', errName: 'NSURLErrorDomain', errMessage: 'The Internet connection appears to be offline.' }),
      context: ctx(),
      stateBefore: S0,
    },
    {
      name: 'sanitize.message-equals-error-not-repeated',
      input: inp({ message: 'timeout', errMessage: '  timeout ' }),
      context: ctx(),
      stateBefore: S0,
    },
    {
      name: 'sanitize.error-only',
      input: inp({ errName: 'TypeError', errMessage: "Cannot read properties of undefined (reading 'rs')" }),
      context: ctx(),
      stateBefore: S0,
    },
    {
      name: 'sanitize.error-message-sanitized',
      input: inp({ errName: 'SocketException', errMessage: 'Failed host lookup: cache.sellwild.com (OS Error: nodename nor servname provided, errno = 8) for jane@x.com' }),
      context: ctx(),
      stateBefore: S0,
    },
  ]
}

function truncation() {
  const m = (name, message, extra = {}) => ({ name, input: inp({ message, ...extra }), context: ctx(), stateBefore: S0 })
  return [
    m('truncate.msg-exactly-200-kept', rep('a', 200)),
    m('truncate.msg-201-cut', rep('a', 201)),
    m('truncate.msg-long-ascii', rep('abcdefghij', 30)),
    m('truncate.msg-emoji-surrogate-pairs', rep('\u{1F600}', 250)),
    m('truncate.msg-emoji-at-cut', rep('a', 199) + '\u{1F600}' + 'bbb'),
    m('truncate.msg-combining-mark-at-cut', rep('a', 198) + 'e\u0301' + 'zzz'),
    m('truncate.msg-zwj-family-at-cut', rep('a', 196) + '\u{1F468}\u200d\u{1F469}\u200d\u{1F467}' + 'zz'),
    m('truncate.msg-flag-pair-at-cut', rep('a', 198) + '\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}'),
    m('truncate.msg-flag-pairs-even-cut', rep('a', 197) + '\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}'),
    m('truncate.msg-skin-tone-at-cut', rep('a', 199) + '\u{1F44D}\u{1F3FD}' + 'z'),
    m('truncate.msg-variation-selector-at-cut', rep('a', 199) + '\u2764\ufe0f' + 'z'),
    m('truncate.msg-cjk', rep('\u6f22', 210)),
    { name: 'truncate.errName-64', input: inp({ errName: 'E' + rep('x', 80) }), context: ctx(), stateBefore: S0 },
    { name: 'truncate.zoneId-32', input: inp({ zoneId: 'weatherbug-mobile-300x250-extra-long-zone-id' }), context: ctx(), stateBefore: S0 },
    { name: 'truncate.partnerCode-64', input: inp(), context: ctx({ partnerCode: rep('p', 70) }), stateBefore: S0 },
    { name: 'truncate.clientVersion-32', input: inp(), context: ctx({ clientVersion: '1.7.7-' + rep('rc', 20) }), stateBefore: S0 },
    { name: 'truncate.release-64', input: inp(), context: ctx({ client: 'widget', clientVersion: '1.1.114', release: rep('0123456789abcdef', 5) }), stateBefore: S0 },
  ]
}

function codes() {
  const c = (name, code) => ({ name, input: { code, component: 'feed' }, context: ctx(), stateBefore: S0 })
  return [
    c('code.valid', 'feed.image.network'),
    c('code.valid-underscore-operation', 'ad.gam_load.exception'),
    c('code.valid-digits', 'ad.s2s_config.parse'),
    c('code.valid-64-chars', 'widget.' + rep('o', 49) + '.invalid'),
    c('code.invalid-65-chars', 'widget.' + rep('o', 50) + '.invalid'),
    c('code.invalid-uppercase', 'Listings.fetch.http'),
    c('code.invalid-two-segments', 'listings.fetch'),
    c('code.invalid-four-segments', 'listings.fetch.http.extra'),
    c('code.invalid-legacy-snake-case', 'listings_fetch_failed'),
    c('code.invalid-leading-digit', '1listings.fetch.http'),
    c('code.invalid-segment-leading-underscore', 'listings._fetch.http'),
    c('code.invalid-hyphen', 'listings.fetch-all.http'),
    c('code.invalid-trailing-newline', 'listings.fetch.http\n'),
    c('code.invalid-surrounding-space', ' listings.fetch.http'),
    c('code.invalid-empty', ''),
    c('code.invalid-null', null),
    c('code.invalid-number', 42),
    c('code.invalid-registry-escape', 'client.code.invalid'),
  ]
}

function components() {
  const c = (name, component) => ({ name, input: { code: 'widget.element.exception', component }, context: ctx({ client: 'widget', clientVersion: '1.1.114' }), stateBefore: S0 })
  return [
    c('component.valid-growthcode', 'growthcode'),
    c('component.valid-remoteConfig', 'remoteConfig'),
    c('component.unknown-value', 'carousel'),
    c('component.case-sensitive', 'Feed'),
    c('component.missing', undefined),
    c('component.number', 7),
  ]
}

function severities() {
  const s = (name, severity, stateBefore = S0) => ({ name, input: inp({ severity }), context: ctx(), stateBefore })
  return [
    s('severity.default-error', undefined),
    s('severity.warn', 'warn'),
    s('severity.invalid-critical-becomes-error', 'critical'),
    s('severity.invalid-uppercase-becomes-error', 'FATAL'),
    s('severity.fatal-flushes-mid-session', 'fatal', state(5, [entry('config.fetch.http|remoteConfig||', NOW - 1000)])),
    s('severity.error-mid-session-no-flush', 'error', state(5, [entry('config.fetch.http|remoteConfig||', NOW - 1000)])),
  ]
}

function dedupe() {
  const d = (name, input, stateBefore, now = NOW) => ({ name, input, context: ctx({ now }), stateBefore })
  const m503 = inp({ message: 'HTTP 503' })
  return [
    d('dedupe.within-window-suppressed', m503, state(1, [entry(K503, NOW - 1000)])),
    d('dedupe.window-59999-suppressed', m503, state(1, [entry(K503, NOW - 59999, 2)])),
    d('dedupe.window-60000-emits-with-repeat', m503, state(1, [entry(K503, NOW - 60000, 4)])),
    d('dedupe.after-window-repeat-1', m503, state(1, [entry(K503, NOW - 600000)])),
    d('dedupe.different-message-new-key', inp({ message: 'HTTP 502' }), state(1, [entry(K503, NOW - 1000)])),
    d('dedupe.same-64-prefix-same-key',
      inp({ message: rep('x', 64) + 'B' }),
      state(1, [entry('listings.fetch.http|listings||' + rep('x', 64), NOW - 1000)])),
    d('dedupe.errName-in-key', inp({ message: 'HTTP 503', errName: 'SellwildError' }), state(1, [entry(K503, NOW - 1000)])),
    d('dedupe.label-in-key', inp({ message: 'HTTP 503', component: 'localized' }), state(1, [entry(K503, NOW - 1000)])),
    d('dedupe.sanitized-message-in-key',
      inp({ message: 'login failed for bob@example.com' }),
      state(1, [entry('listings.fetch.http|listings||login failed for <email>', NOW - 1000)])),
    d('dedupe.clock-backwards-suppressed', m503, state(1, [entry(K503, NOW + 5000)])),
    d('dedupe.fatal-still-deduped', inp({ message: 'HTTP 503', severity: 'fatal' }),
      state(1, [entry('listings.fetch.http|listings||HTTP 503', NOW - 1000)])),
  ]
}

function keyCap() {
  const k = (name, st) => ({ name, input: inp({ message: 'HTTP 503' }), context: ctx(), stateBefore: st })
  return [
    k('keycap.third-emit-allowed', state(2, [entry(K503, NOW - 60000, 1, 2)])),
    k('keycap.fourth-emit-dropped', state(3, [entry(K503, NOW - 600000, 0, 3), entry('config.fetch.http|remoteConfig||', NOW - 1000)])),
    k('keycap.dropped-inside-window-no-suppress-count', state(3, [entry(K503, NOW - 10, 5, 3)])),
  ]
}

function lru() {
  const newKeyInput = inp({ message: 'HTTP 504' })
  return [
    { name: 'lru.new-key-on-full-map-evicts-oldest', input: newKeyInput, context: ctx(), stateBefore: state(3, fill(50)) },
    {
      name: 'lru.existing-key-on-full-map-no-eviction',
      input: { code: 'config.fetch.http', component: 'remoteConfig', message: 'k00' },
      context: ctx(),
      stateBefore: state(3, fill(50)),
    },
    {
      name: 'lru.dedupe-moves-key-to-end',
      input: inp({ message: 'HTTP 503' }),
      context: ctx(),
      stateBefore: state(3, [entry(K503, NOW - 100), entry('a.b.c|feed||', NOW - 50), entry('d.e.f|feed||', NOW - 20)]),
    },
    {
      name: 'lru.key-capped-moves-key-to-end',
      input: inp({ message: 'HTTP 503' }),
      context: ctx(),
      stateBefore: state(3, [entry(K503, NOW - 900000, 0, 3), entry('a.b.c|feed||', NOW - 50)]),
    },
    { name: 'lru.new-key-on-49-entries-no-eviction', input: newKeyInput, context: ctx(), stateBefore: state(3, fill(49)) },
  ]
}

function session() {
  const s = (name, sessionCount, severity) => ({ name, input: inp({ message: 'HTTP 503', severity }), context: ctx(), stateBefore: state(sessionCount) })
  return [
    s('session.19th-not-capped', 18),
    s('session.20th-carries-capped', 19),
    s('session.after-cap-dropped', 20),
    s('session.fatal-after-cap-dropped', 20, 'fatal'),
    s('session.way-past-cap-dropped', 57),
  ]
}

function sampling() {
  const s = (name, rate, extra = {}) => ({
    name,
    input: inp({ severity: extra.severity }),
    context: ctx({ failuresSampleRate: rate, uid: extra.uid ?? UID }),
    stateBefore: S0,
  })
  const boundary = UID_HASH / 4294967296
  return [
    s('sampling.rate-0-drops', 0),
    s('sampling.rate-0-fatal-bypasses', 0, { severity: 'fatal' }),
    s('sampling.rate-1-emits', 1, { uid: UID_VERY_HIGH }),
    s('sampling.rate-half-uid-below-in', 0.5),
    s('sampling.rate-half-uid-above-out', 0.5, { uid: UID_HIGH }),
    s('sampling.rate-string-half-out', '0.5', { uid: UID_HIGH }),
    s('sampling.rate-string-dot5-in', ' .5 ', { uid: UID }),
    s('sampling.rate-empty-string-means-1', '', { uid: UID_VERY_HIGH }),
    s('sampling.rate-above-1-clamped', 2, { uid: UID_VERY_HIGH }),
    s('sampling.rate-negative-clamped-to-0', -1),
    s('sampling.rate-percent-string-means-1', '50%', { uid: UID_VERY_HIGH }),
    s('sampling.rate-boolean-means-1', false, { uid: UID_VERY_HIGH }),
    s('sampling.rate-unresolved-null-means-1', null, { uid: UID_VERY_HIGH }),
    s('sampling.rate-equal-to-hash-is-out', boundary),
    s('sampling.rate-just-above-hash-is-in', (UID_HASH + 1) / 4294967296),
    s('sampling.empty-uid-out', 0.2, { uid: '' }),
    s('sampling.empty-uid-in', 0.3, { uid: '' }),
    s('sampling.fatal-high-uid-rate-0.1', 0.1, { uid: UID_VERY_HIGH, severity: 'fatal' }),
  ]
}

function flags() {
  const ev = (label, value) => ({
    name: `flags.events-${label}`,
    input: inp(),
    context: ctx({ eventsEnabled: value }),
    stateBefore: S0,
  })
  const fl = (label, value) => ({
    name: `flags.failures-${label}`,
    input: inp(),
    context: ctx({ failuresEnabled: value }),
    stateBefore: S0,
  })
  return [
    ev('false-drops', false),
    ev('string-false-drops', 'false'),
    ev('string-FALSE-drops', 'FALSE'),
    ev('string-off-padded-drops', ' off\n'),
    ev('string-no-drops', 'no'),
    ev('string-0-drops', '0'),
    ev('number-0-drops', 0),
    ev('true-emits', true),
    ev('string-true-emits', 'true'),
    ev('string-1-emits', '1'),
    ev('string-empty-emits', ''),
    ev('string-disabled-emits', 'disabled'),
    ev('number-1-emits', 1),
    ev('number-half-emits', 0.5),
    ev('number-negative-emits', -1),
    ev('null-emits', null),
    ev('object-emits', {}),
    ev('array-emits', []),
    fl('false-drops', false),
    fl('string-Off-drops', 'Off'),
    fl('number-0-drops', 0),
    fl('string-empty-emits', ''),
    fl('null-emits', null),
    fl('string-yes-emits', 'yes'),
    {
      name: 'flags.events-off-beats-fatal',
      input: inp({ severity: 'fatal' }),
      context: ctx({ eventsEnabled: false }),
      stateBefore: S0,
    },
    {
      name: 'flags.failures-off-beats-fatal',
      input: inp({ severity: 'fatal' }),
      context: ctx({ failuresEnabled: 'no' }),
      stateBefore: S0,
    },
    {
      name: 'flags.events-off-wins-over-failures-on',
      input: inp(),
      context: ctx({ eventsEnabled: 'off', failuresEnabled: true }),
      stateBefore: S0,
    },
    {
      name: 'flags.unresolved-all-default-on',
      input: inp({ message: 'config not loaded yet', code: 'config.fetch.network', component: 'remoteConfig' }),
      context: { partnerCode: 'weatherbug', client: 'core', clientVersion: '1.7.7', uid: UID_VERY_HIGH, now: NOW },
      stateBefore: S0,
    },
    {
      name: 'flags.drop-leaves-state-untouched',
      input: inp({ message: 'HTTP 503' }),
      context: ctx({ eventsEnabled: false }),
      stateBefore: state(2, [entry(K503, NOW - 1000, 1, 1)]),
    },
  ]
}

function budget() {
  const bigStack = Array.from({ length: 5 }, (_, i) => `at f${i} (${rep('\u{1F600}', 170)}.js:1:1)`).join('\n')
  const accented = rep('\u00e9', 200)
  const b = (name, uidLen, extra = {}) => ({
    name,
    input: inp({ message: accented, errName: 'SellwildError', httpStatus: 503, zoneId: '43', ...extra }),
    context: ctx({ uid: 'u' + rep('0', uidLen - 1), failuresSampleRate: 1 }),
    stateBefore: S0,
  })
  return [
    {
      name: 'budget.under-limit-keeps-everything',
      input: inp({ message: 'HTTP 503', errName: 'SellwildError', stack: 'at a (x.js:1:1)\nat b (y.js:2:2)' }),
      context: ctx({ client: 'android' }),
      stateBefore: S0,
    },
    {
      name: 'budget.stack-dropped-first',
      input: inp({ message: 'HTTP 503', errName: 'SellwildError', stack: bigStack }),
      context: ctx({ client: 'android' }),
      stateBefore: S0,
    },
    b('budget.msg-cut-to-80', 1450),
    b('budget.msg-dropped', 1700),
    b('budget.still-over-sent-without-msg', 2600),
    b('budget.stack-and-msg-cut', 1450, { stack: bigStack }),
  ]
}

function attributes() {
  const a = (name, input, over = {}, stateBefore = S0) => ({ name, input, context: ctx(over), stateBefore })
  return [
    a('attrs.all-16-keys-strings',
      {
        code: 'widget.element.exception', component: 'widget', severity: 'warn', errName: 'TypeError',
        errMessage: 'x is undefined', stack: 'TypeError: x is undefined\n    at render (https://widget.sellwild.com/partner.js:1:2)',
        httpStatus: '200', url: 'https://widget.sellwild.com/weatherbug/weatherbug.json', zoneId: 280,
      },
      { client: 'android', wrapper: 'react-native', release: 'abc1234' },
      state(19)),
    a('attrs.unknown-input-fields-ignored',
      inp({ message: 'HTTP 503', title: '2021 Lexus UX 200', lat: 47.6, email: 'jane@example.com', attributes: { foo: 'bar' }, amount: 3 })),
    a('attrs.http-status-number', inp({ httpStatus: 404 })),
    a('attrs.http-status-string-trimmed', inp({ httpStatus: ' 503 ' })),
    a('attrs.http-status-pattern-omitted', inp({ httpStatus: '5xx' })),
    a('attrs.http-status-two-digits-omitted', inp({ httpStatus: 42 })),
    a('attrs.http-status-fraction-omitted', inp({ httpStatus: 503.5 })),
    a('attrs.http-status-null-omitted', inp({ httpStatus: null })),
    a('attrs.zoneId-number', inp({ zoneId: 43 })),
    a('attrs.zoneId-fraction-omitted', inp({ zoneId: 4.5 })),
    a('attrs.zoneId-blank-omitted', inp({ zoneId: '   ' })),
    a('attrs.zoneId-cleaned', inp({ zoneId: ' zone\n43 ' })),
    a('attrs.wrapper-flutter', inp(), { client: 'android', wrapper: 'flutter' }),
    a('attrs.wrapper-invalid-omitted', inp(), { wrapper: 'unity' }),
    a('attrs.release-widget', { code: 'widget.customelements.unsupported', component: 'widget' }, { client: 'widget', clientVersion: '1.1.114', release: 'f00dbabe' }),
    a('attrs.partnerCode-empty-unknown', inp(), { partnerCode: '' }),
    a('attrs.partnerCode-missing-unknown', inp(), { partnerCode: undefined }),
    a('attrs.clientVersion-missing-unknown', inp(), { clientVersion: null }),
    a('attrs.client-react-native', { code: 'bridge.native_view.missing', component: 'bridge' }, { client: 'react-native' }),
    a('attrs.client-flutter', { code: 'bridge.message.parse', component: 'bridge' }, { client: 'flutter', clientVersion: '1.7.6' }),
    a('attrs.url-host-only', inp({ url: 'https://cache.sellwild.com/listings-img-data-sm-avif-weatherbug?q=secret#frag' })),
    a('attrs.url-invalid-omitted', inp({ url: 'not a url' })),
    a('attrs.url-ip-masked', inp({ url: 'http://52.1.2.3/listings' })),
    a('attrs.url-protocol-relative', inp({ url: '//cache.sellwild.com/listings-img-data-sm' })),
    a('attrs.errName-cleaned', inp({ errName: '  Sellwild\nError  ' })),
    a('attrs.errName-blank-omitted', inp({ errName: ' \t ' })),
  ]
}

function stacks() {
  const s = (name, stack, errName, client = 'android') => ({
    name,
    input: inp({ errName, errMessage: 'boom', stack }),
    context: ctx({ client }),
    stateBefore: S0,
  })
  return [
    s('stack.v8-header-dropped-and-basenamed',
      'TypeError: boom\n    at fetchListings (/Users/jane/app/node_modules/@sellwild/sdk-core/dist/api.js:37:11)\n    at async load (/Users/jane/app/src/Feed.tsx:12:3)',
      'TypeError', 'core'),
    s('stack.first-5-frames', ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map((f, i) => `at ${f} (x.js:${i + 1}:1)`).join('\n'), 'Error', 'core'),
    s('stack.query-removed', 'at load (/static/js/main.js?v=12:1:99)', 'Error', 'widget'),
    s('stack.url-becomes-host', 'at render (https://widget.sellwild.com/partner.js?cb=1:1:234567)', 'Error', 'widget'),
    s('stack.jsc-at-sign-format', 'render@https://widget.sellwild.com/partner.js:1:2\nglobal code@https://example.com/page.html:3:4', 'Error', 'widget'),
    s('stack.dart-file-url-basename', '#0      SellwildAPIClient.fetchListings (package:sellwild_sdk/src/sellwild_api.dart:19:7)\n#1      main (file:///Users/jane/app/lib/main.dart:3:5)', 'SellwildException', 'flutter'),
    s('stack.kotlin-frames-kept', 'com.sellwild.sdk.SellwildAPIClient.fetchListings(SellwildAPI.kt:122)\ncom.sellwild.sdk.SellwildFeedView.load(SellwildFeedView.kt:252)', 'SellwildException'),
    s('stack.header-kept-when-name-differs', 'Error: boom\n    at f (a.js:1:1)', 'TypeError', 'core'),
    s('stack.only-header-omitted', 'TypeError: boom', 'TypeError', 'core'),
    s('stack.blank-omitted', '\n \n', 'TypeError', 'core'),
    s('stack.pii-masked', 'at login (jane@example.com)\nat order (a/2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11.js:1:1)\nat net (10.1.2.3)', 'Error', 'core'),
    s('stack.truncated-800', Array.from({ length: 5 }, (_, i) => `at fn${i} (${rep('m', 190)}.js:1:1)`).join('\n'), 'Error', 'core'),
    s('stack.crlf-lines', 'Error: boom\r\n   at a (x.js:1:1)\r\n   at b (y.js:2:2)\r\n', 'Error', 'core'),
  ]
}

export function buildCases() {
  return [
    ...basic(),
    ...sanitize(),
    ...truncation(),
    ...codes(),
    ...components(),
    ...severities(),
    ...dedupe(),
    ...keyCap(),
    ...lru(),
    ...session(),
    ...sampling(),
    ...flags(),
    ...budget(),
    ...attributes(),
    ...stacks(),
  ]
}

// Single-function tables for porting and debugging. Expected values are
// computed by the reference, like the full vectors.
export const UNIT_INPUTS = {
  fnv1a32: ['', 'a', 'foobar', UID + ':failures', UID_HIGH + ':failures', ':failures', '\u00e9', '\u{1F600}'],
  truncateUnicode: [
    ['abcdef', 4], ['abc', 3], ['abcd', 3], ['ab\u{1F600}cd', 4], ['ab\u{1F600}cd', 3], ['abce\u0301f', 5],
    ['a\u{1F468}\u200d\u{1F469}\u200d\u{1F467}b', 5], ['x\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}', 4],
    ['x\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}', 3], ['\u0301\u0301\u0301', 2],
  ],
  hostOf: [
    'https://cache.sellwild.com/listings-img-data-sm', 'HTTPS://Example.COM.', '//a.b/c', 'http://[::1]:80/',
    'ftp://1.2.3.4/x', 'nope', 'https://user:pw@host.example:8443/p?q#f', 'file:///tmp/x', 'http://', '  https://x.io  ',
    'https://b\u00fccher.de/x', 'mailto:jane@example.com',
  ],
  sanitizeMessage: [
    'jane@example.com', 'id 123456', 'id 12345', 'see https://a.b/c?d=e', 'x\u0000y', '  a   b  ',
    '2d0f7a0a-9d1f-4c35-9d8b-0a1f2f9a8c11', '192.168.0.1', '1.2.3.4.5', 'v1.7.7',
  ],
  coerceFlag: [true, false, 0, 1, -1, 0.5, 'false', 'FALSE', ' off ', 'no', '0', '', 'true', 'nope', null, {}, []],
  coerceRate: [0, 1, 0.25, 2, -1, '0.5', ' .5 ', '+0.5', '1.', '', '50%', 'abc', '1e-1', null, true, {}],
  normalizeCode: ['config.fetch.http', 'CONFIG.fetch.http', 'config.fetch', 'config.fetch.http\n', 'a.b.c', 'a.b_.c_', 'a1.b2.c3'],
  normalizeHttpStatus: [503, '503', ' 404 ', 42, 1000, 503.5, '5xx', '0503', null],
}

// Lone surrogates cannot live in a Swift String, and Foundation's JSON parser
// rejects them, so these go to a separate file that only UTF-16 platforms read.
export const UTF16_ONLY_CASES = [
  { name: 'utf16.lone-high-surrogate-replaced', input: inp({ message: 'bad \ud800 half' }), context: ctx(), stateBefore: S0 },
  { name: 'utf16.lone-low-surrogate-replaced', input: inp({ message: 'bad \udc00 low', errName: 'E\udfff' }), context: ctx(), stateBefore: S0 },
  { name: 'utf16.lone-surrogate-in-zoneId', input: inp({ zoneId: 'z\ud83d' }), context: ctx(), stateBefore: S0 },
]

export const UTF16_ONLY_UNITS = {
  fnv1a32: ['\ud800', 'a\udc00b'],
  sanitizeMessage: ['bad \udc00 low', '😀 ok \ud83d'],
}
