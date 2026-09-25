// The golden vectors are exactly what the reference produces, and a set of
// vectors is checked against literal values worked out by hand from
// FAILURES.md (not copied from the reference output).

import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import * as L from '../reference/log-failure.mjs'
import { generate, serialize, VECTORS_PATH, UTF16_VECTORS_PATH } from '../scripts/generate-vectors.mjs'

const main = JSON.parse(fs.readFileSync(VECTORS_PATH, 'utf8'))
const utf16 = JSON.parse(fs.readFileSync(UTF16_VECTORS_PATH, 'utf8'))
const byName = Object.fromEntries([...main.vectors, ...utf16.vectors].map((v) => [v.name, v]))
const vec = (name) => {
  const v = byName[name]
  assert.ok(v, `vector ${name} exists`)
  return v.expected
}
const NOW = 1790000000000
const UID = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11'

test('committed vector files equal a fresh regeneration', () => {
  const fresh = generate()
  assert.equal(fs.readFileSync(VECTORS_PATH, 'utf8'), serialize(fresh.main))
  assert.equal(fs.readFileSync(UTF16_VECTORS_PATH, 'utf8'), serialize(fresh.utf16))
})

test('every vector replays through decideFailure to its expected output', () => {
  for (const v of [...main.vectors, ...utf16.vectors]) {
    const r = L.decideFailure(v.stateBefore, v.input, v.context, v.context.uid, v.context.now)
    assert.deepEqual(
      { event: r.event, flushNow: r.flushNow, reason: r.reason, stateAfter: r.state },
      v.expected,
      v.name,
    )
  }
})

test('there are at least 80 vectors and every rule family is present', () => {
  assert.ok(main.vectors.length >= 80, `${main.vectors.length} vectors`)
  const families = new Set(main.vectors.map((v) => v.name.split('.')[0]))
  for (const f of ['basic', 'sanitize', 'truncate', 'code', 'component', 'severity', 'dedupe', 'keycap', 'lru', 'session', 'sampling', 'flags', 'budget', 'attrs', 'stack']) {
    assert.ok(families.has(f), `family ${f}`)
  }
})

test('reference state is never mutated in place', () => {
  const before = { sessionCount: 1, keys: [{ key: 'listings.fetch.http|listings||HTTP 503', lastEmitAt: NOW - 1000, suppressed: 0, emits: 1 }] }
  const snapshot = JSON.stringify(before)
  L.decideFailure(before, { code: 'listings.fetch.http', component: 'listings', message: 'HTTP 503' }, { partnerCode: 'p', client: 'core', clientVersion: '1' }, UID, NOW)
  assert.equal(JSON.stringify(before), snapshot)
})

// ── Hand-checked values ──────────────────────────────────────────────────────

test('hand: FNV-1a 32 published test values', () => {
  assert.equal(L.fnv1a32(''), 0x811c9dc5)
  assert.equal(L.fnv1a32('a'), 0xe40c292c)
  assert.equal(L.fnv1a32('foobar'), 0xbf9cf968)
})

test('hand: first failure of the session is a full event and flushes', () => {
  assert.deepEqual(vec('basic.first-failure-flushes'), {
    event: {
      event: 'clientFailure',
      action: 'listings.fetch.http',
      label: 'listings',
      attributes: {
        code: 'weatherbug', client: 'ios', clientVersion: '1.7.7', severity: 'error', fv: '1',
        msg: 'HTTP 503', httpStatus: '503', host: 'cache.sellwild.com', zoneId: '43', seq: '1', repeat: '1',
      },
      uid: UID,
      createdTime: NOW,
    },
    flushNow: true,
    reason: null,
    stateAfter: { sessionCount: 1, keys: [{ key: 'listings.fetch.http|listings||HTTP 503', lastEmitAt: NOW, suppressed: 0, emits: 1 }] },
  })
})

test('hand: sanitizing masks emails, digits, URLs and control characters', () => {
  assert.equal(vec('sanitize.email').event.attributes.msg, 'login failed for <email>')
  assert.equal(vec('sanitize.url-userinfo-port-case').event.attributes.msg, 'fetch widget.sellwild.com')
  assert.equal(vec('sanitize.digits-long-run-and-embedded').event.attributes.msg, 'phone <n> ref abc<n>xyz')
  assert.equal(vec('sanitize.digits-5-kept').event.attributes.msg, 'zip 90210 and code 12345')
  assert.equal(vec('sanitize.uuid-upper').event.attributes.msg, 'idfa=<id>')
  assert.equal(vec('sanitize.control-chars').event.attributes.msg, 'a b c d e f')
  assert.equal(vec('sanitize.message-and-error-joined').event.attributes.msg, 'listings request failed: The Internet connection appears to be offline.')
  assert.equal(vec('sanitize.blank-message-omitted').event.attributes.msg, undefined)
  assert.equal(vec('utf16.lone-high-surrogate-replaced').event.attributes.msg, 'bad � half')
})

test('hand: truncation keeps surrogate pairs and combining marks whole', () => {
  assert.equal(vec('truncate.msg-emoji-surrogate-pairs').event.attributes.msg, '\u{1F600}'.repeat(199) + '…')
  assert.equal(vec('truncate.msg-combining-mark-at-cut').event.attributes.msg, 'a'.repeat(198) + '…')
  assert.equal(vec('truncate.msg-exactly-200-kept').event.attributes.msg, 'a'.repeat(200))
  assert.equal(vec('truncate.msg-201-cut').event.attributes.msg, 'a'.repeat(199) + '…')
  assert.equal(vec('truncate.zoneId-32').event.attributes.zoneId, 'weatherbug-mobile-300x250-extra…')
})

test('hand: invalid codes and unknown components are replaced', () => {
  assert.equal(vec('code.invalid-trailing-newline').event.action, 'client.code.invalid')
  assert.equal(vec('code.invalid-legacy-snake-case').event.action, 'client.code.invalid')
  assert.equal(vec('code.valid-underscore-operation').event.action, 'ad.gam_load.exception')
  assert.equal(vec('component.case-sensitive').event.label, 'unknown')
  assert.equal(vec('severity.invalid-critical-becomes-error').event.attributes.severity, 'error')
})

test('hand: dedupe window, repeat count and per-key cap', () => {
  const inside = vec('dedupe.within-window-suppressed')
  assert.equal(inside.event, null)
  assert.equal(inside.reason, 'deduped')
  assert.deepEqual(inside.stateAfter, { sessionCount: 1, keys: [{ key: 'listings.fetch.http|listings||HTTP 503', lastEmitAt: NOW - 1000, suppressed: 1, emits: 1 }] })

  const after = vec('dedupe.window-60000-emits-with-repeat')
  assert.equal(after.event.attributes.repeat, '5')
  assert.equal(after.event.attributes.seq, '2')
  assert.equal(after.flushNow, false)
  assert.deepEqual(after.stateAfter.keys, [{ key: 'listings.fetch.http|listings||HTTP 503', lastEmitAt: NOW, suppressed: 0, emits: 2 }])

  assert.equal(vec('keycap.third-emit-allowed').stateAfter.keys[0].emits, 3)
  assert.equal(vec('keycap.fourth-emit-dropped').reason, 'key_capped')
})

test('hand: LRU keeps 50 keys and drops the least recently used', () => {
  const r = vec('lru.new-key-on-full-map-evicts-oldest')
  assert.equal(r.stateAfter.keys.length, 50)
  assert.equal(r.stateAfter.keys[0].key, 'config.fetch.http|remoteConfig||k01')
  assert.equal(r.stateAfter.keys[49].key, 'listings.fetch.http|listings||HTTP 504')
})

test('hand: the 20th event carries capped and later ones are dropped', () => {
  const twentieth = vec('session.20th-carries-capped')
  assert.equal(twentieth.event.attributes.seq, '20')
  assert.equal(twentieth.event.attributes.capped, '1')
  assert.equal(vec('session.19th-not-capped').event.attributes.capped, undefined)
  assert.equal(vec('session.after-cap-dropped').reason, 'session_capped')
  assert.equal(vec('session.fatal-after-cap-dropped').event, null)
})

test('hand: sampling by uid hash, and fatal bypasses it', () => {
  // fnv1a32('uid-d:failures') / 2^32 ≈ 0.519 > 0.5, and 0.229 for UID.
  assert.equal(vec('sampling.rate-half-uid-above-out').reason, 'sampled_out')
  assert.notEqual(vec('sampling.rate-half-uid-below-in').event, null)
  assert.equal(vec('sampling.rate-0-drops').reason, 'sampled_out')
  const fatal = vec('sampling.rate-0-fatal-bypasses')
  assert.notEqual(fatal.event, null)
  assert.equal(fatal.flushNow, true)
  assert.equal(vec('sampling.rate-equal-to-hash-is-out').event, null)
  assert.notEqual(vec('sampling.rate-boolean-means-1').event, null)
})

test('hand: kill switch coercion', () => {
  assert.equal(vec('flags.events-string-off-padded-drops').reason, 'events_disabled')
  assert.equal(vec('flags.events-number-0-drops').reason, 'events_disabled')
  assert.notEqual(vec('flags.events-string-disabled-emits').event, null)
  assert.notEqual(vec('flags.events-string-empty-emits').event, null)
  assert.equal(vec('flags.failures-string-Off-drops').reason, 'failures_disabled')
  assert.equal(vec('flags.events-off-beats-fatal').event, null)
  assert.notEqual(vec('flags.unresolved-all-default-on').event, null)
})

test('hand: size budget drops stack, then cuts msg to 80, then drops msg', () => {
  const stackDropped = vec('budget.stack-dropped-first').event.attributes
  assert.equal(stackDropped.stack, undefined)
  assert.equal(stackDropped.msg, 'HTTP 503')
  const cut = vec('budget.msg-cut-to-80').event.attributes.msg
  assert.equal([...cut].length, 80)
  assert.equal(cut, 'é'.repeat(79) + '…')
  assert.equal(vec('budget.msg-dropped').event.attributes.msg, undefined)
  assert.equal(vec('budget.under-limit-keeps-everything').event.attributes.stack, 'at a (x.js:1:1)\nat b (y.js:2:2)')
})

test('hand: all 16 attributes are strings and unknown input fields never appear', () => {
  const attrs = vec('attrs.all-16-keys-strings').event.attributes
  assert.equal(Object.keys(attrs).length, 16)
  for (const [k, v] of Object.entries(attrs)) assert.equal(typeof v, 'string', k)
  const ev = vec('attrs.unknown-input-fields-ignored').event
  assert.deepEqual(Object.keys(ev), ['event', 'action', 'label', 'attributes', 'uid', 'createdTime'])
  assert.equal(JSON.stringify(ev).includes('Lexus'), false)
  assert.equal(JSON.stringify(ev).includes('jane@'), false)
  assert.equal(vec('attrs.http-status-number').event.attributes.httpStatus, '404')
  assert.equal(vec('attrs.http-status-pattern-omitted').event.attributes.httpStatus, undefined)
  assert.equal(vec('attrs.zoneId-number').event.attributes.zoneId, '43')
  assert.equal(vec('attrs.url-host-only').event.attributes.host, 'cache.sellwild.com')
  assert.equal(vec('attrs.url-ip-masked').event.attributes.host, '<ip>')
  assert.equal(vec('attrs.partnerCode-empty-unknown').event.attributes.code, 'unknown')
})

test('hand: stacks keep 5 frames with basenames and hosts only', () => {
  assert.equal(vec('stack.v8-header-dropped-and-basenamed').event.attributes.stack, 'at fetchListings (api.js:37:11)\nat async load (Feed.tsx:12:3)')
  assert.equal(vec('stack.query-removed').event.attributes.stack, 'at load (main.js:1:99)')
  assert.equal(vec('stack.url-becomes-host').event.attributes.stack, 'at render (widget.sellwild.com)')
  assert.equal(vec('stack.first-5-frames').event.attributes.stack.split('\n').length, 5)
  assert.equal(vec('stack.only-header-omitted').event.attributes.stack, undefined)
})

test('hand: unit tables', () => {
  assert.equal(L.hostOf('https://user:pw@host.example:8443/p?q#f'), 'host.example')
  assert.equal(L.hostOf('http://[::1]:80/'), '<ip>')
  assert.equal(L.hostOf('HTTPS://Example.COM.'), 'example.com')
  assert.equal(L.hostOf('nope'), null)
  assert.equal(L.coerceRate(' .5 '), 0.5)
  assert.equal(L.coerceRate('50%'), 1)
  assert.equal(L.coerceRate(-1), 0)
  assert.equal(L.coerceRate(true), 1)
  assert.equal(L.coerceFlag(' OFF '), false)
  assert.equal(L.coerceFlag({}), true)
  assert.equal(L.truncateUnicode('x\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}', 3), 'x…')
  assert.equal(L.truncateUnicode('a\u{1F468}‍\u{1F469}‍\u{1F467}b', 5), 'a…')
})

test('hand: edge inputs every port must also accept', () => {
  // Tag characters and supplementary variation selectors stay with their base.
  assert.equal(L.truncateUnicode('ab\u{E0041}cdef', 3), 'a…')
  assert.equal(L.truncateUnicode('ab\u{E0100}cdef', 3), 'a…')
  assert.equal(L.truncateUnicode('ab\u{E01F0}cdef', 3), 'ab…', 'U+E01F0 is past the selector block')
  assert.equal(L.truncateUnicode(null, 3), null)
  assert.equal(L.cleanText(42), '')
  assert.equal(L.hostOf('https://[::1'), null, 'an unclosed IPv6 bracket has no host')
  // A URL frame with no host keeps its basename; a query cuts it; an empty one is <url>.
  assert.equal(
    L.sanitizeStack('at f (file:///a/b/c.js?v=1)\nat g (file:///a/b/d.js:3:4)\nat h (file:///?q)', null),
    'at f (c.js)\nat g (d.js:3:4)\nat h (<url>)',
  )
  assert.equal(L.coerceRate(Infinity), 1)
  assert.equal(L.coerceRate(NaN), 1)
  assert.equal(L.fnv1a32(undefined), L.fnv1a32(''))
  assert.equal(L.isSampled(undefined, 0.5), L.isSampled('', 0.5))
  assert.equal(L.dedupeKey('a.b.c', 'feed', null, null), 'a.b.c|feed||')
  const event = { event: 'e', action: 'a', label: 'l', attributes: { msg: 'q"\\\b\f\n\r\t\u0001/é' }, uid: 'u', createdTime: 1 }
  assert.equal(L.canonicalJson(event), '{"event":"e","action":"a","label":"l","attributes":{"msg":"q\\"\\\\\\b\\f\\n\\r\\t\\u0001/é"},"uid":"u","createdTime":1}')
  const fields = { action: 'a.b.c', label: 'feed', severity: 'error', seq: 1, repeat: 1 }
  const bare = L.buildFailureEvent(fields, null, 7, NOW)
  assert.deepEqual([bare.attributes.code, bare.attributes.client, bare.attributes.clientVersion, bare.uid], ['unknown', 'unknown', 'unknown', ''])
  assert.equal(L.buildFailureEvent(fields, { client: '' }, UID, NOW).attributes.client, 'unknown')
  // No state, input or context: a fresh state and an invalid code, still one event.
  const r = L.decideFailure(undefined, undefined, undefined, UID, NOW)
  assert.deepEqual([r.event.action, r.event.label, r.reason, r.state.sessionCount], ['client.code.invalid', 'unknown', null, 1])
})

test('the shell input cap: first 1000 units of message, 2000 of stack, a split pair becomes U+FFFD', () => {
  assert.deepEqual(L.INPUT_LIMITS, { message: 1000, errMessage: 1000, stack: 2000 })
  assert.equal(L.capInput('abc', 3), 'abc')
  assert.equal(L.capInput('abcd', 3), 'abc')
  assert.equal(L.capInput(null, 3), null)
  assert.equal(L.capInput(42, 1), 42)
  // 998 digits mask to <n>, so only the 2 letters inside the cap reach the message.
  const long = `${'1'.repeat(998)}ABCDEFG`
  assert.equal(L.sanitizeMessage(L.capInput(long, L.INPUT_LIMITS.message)), '<n>AB')
  assert.equal(L.sanitizeMessage(L.capInput(`${'1'.repeat(999)}\u{1F600}tail`, L.INPUT_LIMITS.message)), '<n>\uFFFD')
  const r = L.decideFailure(L.initialState(), { code: 'listings.fetch.http', component: 'listings', message: L.capInput(long, 1000) }, { partnerCode: 'p', client: 'ios', clientVersion: '1' }, UID, NOW)
  assert.equal(r.event.attributes.msg, '<n>AB')
})
