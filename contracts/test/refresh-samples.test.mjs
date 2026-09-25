// Guard logic only. No test here reaches the network: every fetch is a stub.

import test from 'node:test'
import assert from 'node:assert/strict'
import { assertAllowedRequest, guardedGet, refresh } from '../scripts/refresh-samples.mjs'
import { SAMPLE_SPECS } from '../scripts/lib/samples.mjs'

const refusingFetch = () => {
  const calls = []
  const fn = async (...args) => {
    calls.push(args)
    throw new Error('network must not be reached')
  }
  fn.calls = calls
  return fn
}

test('allowlisted GETs pass', () => {
  for (const url of [
    'https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json',
    'https://cache.sellwild.com/listings-img-data-sm',
    'https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-al.json',
  ]) {
    assert.equal(assertAllowedRequest(url, 'GET').hostname.length > 0, true, url)
  }
})

test('events.sellwild.com is refused for every method and path', () => {
  for (const method of ['GET', 'POST', 'PUT']) {
    for (const url of ['https://events.sellwild.com/events/queue', 'https://events.sellwild.com/', 'http://events.sellwild.com/x', 'https://a.events.sellwild.com/q']) {
      assert.throws(() => assertAllowedRequest(url, method), /refused/, `${method} ${url}`)
    }
  }
})

test('any method other than GET is refused, even to an allowlisted host', () => {
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'get']) {
    assert.throws(() => assertAllowedRequest('https://cache.sellwild.com/listings-sm', method), /only GET/, method)
  }
})

test('lookalike hosts, other paths, http, ports and credentials are refused', () => {
  for (const url of [
    'https://cache.sellwild.com.evil.example/listings-sm',
    'https://evilcache.sellwild.com/listings-sm',
    'https://widget.sellwild.com/weatherbug/weatherbug-weatherbug.json',
    'https://widget.sellwild.com/partner.js',
    'http://cache.sellwild.com/listings-sm',
    'https://cache.sellwild.com:8443/listings-sm',
    'https://user:pw@cache.sellwild.com/listings-sm',
    'https://api.sellwild.com/session/rpc',
    'https://ids.api.gcprivacy.id/v4/sync/api',
    'not a url',
  ]) {
    assert.throws(() => assertAllowedRequest(url, 'GET'), /refused/, url)
  }
})

test('every refreshable sample URL passes the guard', () => {
  for (const s of SAMPLE_SPECS.filter((x) => x.refreshable !== false)) assert.doesNotThrow(() => assertAllowedRequest(s.url, 'GET'), s.file)
})

test('guardedGet checks before calling fetch, sends GET without following redirects', async () => {
  const blocked = refusingFetch()
  await assert.rejects(guardedGet('https://events.sellwild.com/events/queue', blocked), /refused/)
  assert.equal(blocked.calls.length, 0)

  const seen = []
  const redirecting = async (url, init) => {
    seen.push(init)
    return { status: 302, headers: new Map(), arrayBuffer: async () => new ArrayBuffer(0) }
  }
  await assert.rejects(guardedGet('https://cache.sellwild.com/listings-sm', redirecting), /redirect/)
  assert.deepEqual(seen, [{ method: 'GET', redirect: 'manual' }])
})

test('refresh refuses without CONTRACTS_LIVE=1 and never calls fetch', async () => {
  const f = refusingFetch()
  await assert.rejects(refresh({ fetchImpl: f, env: {}, write: false }), /CONTRACTS_LIVE=1/)
  await assert.rejects(refresh({ fetchImpl: f, env: { CONTRACTS_LIVE: 'true' }, write: false }), /CONTRACTS_LIVE=1/)
  assert.equal(f.calls.length, 0)
})

test('refresh with a stub only GETs allowlisted URLs and reports status drift', async () => {
  const urls = []
  const stub = async (url, init) => {
    assert.equal(init.method, 'GET')
    urls.push(url)
    const status = url.endsWith('-zz.json') || url.includes('realgm') || url.includes('weatherbug-main') ? 403 : 200
    const body = status === 403 ? '<Error><Code>AccessDenied</Code></Error>' : url.includes('/app/') ? '{"CODE":"x"}' : '{"result":{"rs":[]}}'
    return { status: url.includes('antengo') ? 403 : status, headers: new Map([['content-type', 'application/json']]), arrayBuffer: async () => new TextEncoder().encode(body).buffer }
  }
  const r = await refresh({ fetchImpl: stub, env: { CONTRACTS_LIVE: '1' }, write: false, today: '2026-09-24' })
  for (const u of urls) assert.doesNotThrow(() => assertAllowedRequest(u, 'GET'), u)
  assert.equal(new Set(urls).size, urls.length, 'each URL fetched once')
  assert.deepEqual(r.statusChanged, [{ file: 'app-config/antengo_antengo-sellwild-tv.json', expected: 200, got: 403 }])
  assert.ok(r.entries.every((e) => e.fetchedAt === '2026-09-24' || e.refreshable === false || e.file.includes('antengo')))
})
