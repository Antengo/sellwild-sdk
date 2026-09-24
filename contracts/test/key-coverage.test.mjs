// Every CONSTANT_CASE remote-config key that SDK code reads, on any platform,
// is declared in schemas/app-config.schema.json.

import test from 'node:test'
import assert from 'node:assert/strict'
import { remoteKeysInRepo, keysInSource, NOT_CONFIG_KEYS, SHORT_TOKEN } from '../scripts/lib/remote-keys.mjs'
import { readSchema } from '../scripts/lib/schemas.mjs'

const appConfig = readSchema('app-config')
const declared = new Set(Object.keys(appConfig.properties))
const bridgeTypes = new Set(readSchema('bridge-message').oneOf.map((b) => b.properties.type.const))

test('every remote key read by SDK code is declared in app-config.schema.json', () => {
  const found = remoteKeysInRepo()
  assert.ok(found.size > 100, `only ${found.size} candidate keys found; the scan is broken`)
  const undeclared = []
  for (const [key, files] of found) {
    if (declared.has(key) || bridgeTypes.has(key) || NOT_CONFIG_KEYS[key] || SHORT_TOKEN.test(key)) continue
    undeclared.push(`${key} (${files.join(', ')})`)
  }
  assert.deepEqual(undeclared, [], `declare these keys in app-config.schema.json, or add them to NOT_CONFIG_KEYS with a reason:\n${undeclared.join('\n')}`)
})

test('the scan sees keys from every platform, including the new failure flags once read', () => {
  const found = remoteKeysInRepo()
  const platformsOf = (key) => new Set((found.get(key) ?? []).map((f) => f.split('/')[0]))
  const events = platformsOf('EVENTS_ENABLED')
  for (const p of ['core', 'ios', 'android']) assert.ok(events.has(p), `EVENTS_ENABLED read in ${p}`)
  assert.ok(platformsOf('MOBILE_ZID').has('flutter'))
  assert.ok(platformsOf('APP_BUNDLE_ID_IOS').has('react-native'))
  for (const k of ['EVENTS_ENABLED', 'FAILURES_ENABLED', 'FAILURES_SAMPLE_RATE']) assert.ok(declared.has(k), `${k} declared`)
})

test('bridge message types found in code are the ones the bridge schema declares', () => {
  const found = remoteKeysInRepo()
  for (const t of ['LISTING_CLICK', 'AD_IMPRESSION', 'WIDGET_LOADED', 'ERROR']) {
    assert.ok(found.has(t), `${t} used in code`)
    assert.ok(bridgeTypes.has(t), `${t} declared`)
  }
})

test('extraction reads quoted literals and KEY_MAP keys, not comments', () => {
  const ts = [
    'const KEY_MAP: Record<string, string> = {',
    "  CODE: 'partnerCode',",
    '  // OLD_KEY: "x",',
    "  EVENTS_ENABLED: 'eventsEnabled',",
    '}',
    "const a = raw['LOCALIZED_LISTINGS'] // 'COMMENT_KEY'",
    "const url = 'https://x.io/a' + 'LATE_KEY'",
  ].join('\n')
  assert.deepEqual([...keysInSource(ts, 'ts')].sort(), ['CODE', 'EVENTS_ENABLED', 'LATE_KEY', 'LOCALIZED_LISTINGS'])
  const swift = 'let v = raw["MOBILE_ZID_IOS"] as? [String] /* raw["BLOCK_KEY"] */\n/// raw["DOC_KEY"]'
  assert.deepEqual([...keysInSource(swift, 'swift')], ['MOBILE_ZID_IOS'])
  const kotlin = 'val x = obj.optString("GAM") // "LINE_KEY"\nval y = "${obj.optString("NESTED_KEY")}"'
  assert.deepEqual([...keysInSource(kotlin, 'kotlin')].sort(), ['GAM', 'NESTED_KEY'])
  const dart = "final v = raw['AD_STACK']; // raw['X_KEY']\nfinal s = 'lower_case';"
  assert.deepEqual([...keysInSource(dart, 'dart')], ['AD_STACK'])
})
