import { beforeEach, describe, expect, it, vi } from 'vitest'
import accessDenied from '../../contracts/samples/localized-listings-response/sports-img-data-sm-webp-zz.403.xml?raw'
import {
  buildTagCacheUrl,
  clearListingCache,
  fetchListings,
  fetchTagCacheListings,
  hasListingsArray,
  parseListingsResponse,
  parseTagCacheResponse,
  resolveListingsUrl,
} from '../src/api'
import { buildConfig, DEFAULT_LISTINGS_URL } from '../src/config'
import { invalidListingsResponse, listing, listingsResponse, tagCacheResponse } from './factories'
import { expectInvalid, expectValid } from './support/factory-checks'
import { validate } from './support/schemas'
import { countLogFailureCalls, takeFailureEvents, takeRecordedFailures } from './support/failures'

const LISTINGS_URL = 'https://cache.sellwild.com/listings-img-data-sm'
const config = buildConfig({ partnerCode: 'weatherbug', listingsUrl: LISTINGS_URL })

type FetchImpl = (url: string, init: RequestInit) => Promise<Response>

function stubFetch(impl: FetchImpl) {
  const fetchMock = vi.fn(impl)
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

const answer = (body: string, status = 200) => async () => new Response(body, { status })
const json = (body: unknown, status = 200) => answer(JSON.stringify(body), status)

describe('resolveListingsUrl', () => {
  it('uses listingsUrl, else the general listings cache', () => {
    expect(resolveListingsUrl(config)).toBe(LISTINGS_URL)
    expect(resolveListingsUrl(buildConfig({ partnerCode: 'p' }))).toBe(DEFAULT_LISTINGS_URL)
  })
})

describe('fetchListings', () => {
  beforeEach(() => {
    clearListingCache()
  })

  it('returns the listings, config and cache version of a real cache response', async () => {
    const body = listingsResponse({ config: { browse: 1 }, widgetCacheVersionId: '733489' })
    const fetchMock = stubFetch(json(body))
    const controller = new AbortController()

    const result = await fetchListings(config, { signal: controller.signal, headers: { 'X-Test': '1' } })

    expect(fetchMock).toHaveBeenCalledExactlyOnceWith(LISTINGS_URL, { signal: controller.signal, headers: { 'X-Test': '1' } })
    expect(result).toEqual({ listings: body.result.rs, config: { browse: 1 }, widgetCacheVersionId: '733489' })
  })

  it('unwraps result.listings, a bare body, and defaults config and version, without a report', async () => {
    // Older shapes the contract no longer allows: listings in result.listings,
    // and the result object on its own.
    const inListings = listingsResponse({ rs: undefined as never, listings: [listing()] })
    expectInvalid('listings-response', inListings, { instancePath: '/result', keyword: 'required' })
    stubFetch(json(inListings))
    await expect(fetchListings(config)).resolves.toEqual({ listings: [listing()], config: {}, widgetCacheVersionId: '0' })

    clearListingCache()
    const bare = listingsResponse({ rs: [listing()], widgetCacheVersionId: '12' }).result
    expectInvalid('listings-response', bare, { instancePath: '', keyword: 'required' })
    stubFetch(json(bare))
    await expect(fetchListings(config)).resolves.toMatchObject({ listings: [listing()], widgetCacheVersionId: '12' })

    expect(takeFailureEvents()).toEqual([])
  })

  it('shares one request per URL until the cache is cleared', async () => {
    const fetchMock = stubFetch(json(listingsResponse()))

    const [a, b] = await Promise.all([fetchListings(config), fetchListings(config)])
    await fetchListings(config)
    clearListingCache()
    await fetchListings(config)

    expect(a).toBe(b)
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('reports a network error, rejects with it, and retries on the next call', async () => {
    const offline = new TypeError('Network request failed')
    const fetchMock = stubFetch(async () => {
      throw offline
    })

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchListings(config)).rejects.toBe(offline)
      fetchMock.mockImplementation(json(listingsResponse()))
      await expect(fetchListings(config)).resolves.toMatchObject({ listings: expect.any(Array) })
    })

    expect(calls).toEqual({ 'listings.fetch.network': 1 })
    expect(takeFailureEvents()).toMatchObject([
      {
        action: 'listings.fetch.network',
        label: 'listings',
        attributes: { errName: 'TypeError', msg: 'Network request failed', host: 'cache.sellwild.com' },
      },
    ])
  })

  it('does not report a caller abort', async () => {
    const controller = new AbortController()
    stubFetch(async () => {
      controller.abort()
      throw new DOMException('This operation was aborted', 'AbortError')
    })

    await expect(fetchListings(config, { signal: controller.signal })).rejects.toThrow('aborted')
    expect(takeFailureEvents()).toEqual([])
  })

  it('reports a non-2xx answer once and still parses a JSON body, as it always has', async () => {
    stubFetch(json(listingsResponse({ rs: [] }), 503))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchListings(config)).resolves.toMatchObject({ listings: [] })
    })

    expect(calls).toEqual({ 'listings.fetch.http': 1 })
    expect(takeFailureEvents()).toMatchObject([
      { action: 'listings.fetch.http', attributes: { msg: 'HTTP 503', httpStatus: '503', host: 'cache.sellwild.com' } },
    ])
  })

  it('reports a 403 XML answer once, as HTTP, and rejects with the parse error', async () => {
    stubFetch(answer(accessDenied, 403))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchListings(config)).rejects.toThrow(SyntaxError)
    })

    expect(calls).toEqual({ 'listings.fetch.http': 1 })
    expect(takeFailureEvents().map((e) => [e.action, e.attributes.httpStatus])).toEqual([['listings.fetch.http', '403']])
  })

  it('reports a non-2xx JSON body without listings once, as HTTP', async () => {
    // An error body in place of the envelope: {"message":"Internal Server Error"} on the wire.
    const body = { ...listingsResponse(), result: undefined as never, message: 'Internal Server Error' }
    expectInvalid('listings-response', body, { instancePath: '', keyword: 'required' })
    stubFetch(json(body, 500))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchListings(config)).resolves.toEqual({ listings: [], config: {}, widgetCacheVersionId: '0' })
    })

    expect(calls).toEqual({ 'listings.fetch.http': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.http'])
  })

  it('reports a 200 body that is not JSON once, by the error name only, and rejects with the parse error', async () => {
    stubFetch(answer('<html>502 Bad Gateway</html>'))

    const calls = await countLogFailureCalls(async () => {
      // The caller still gets the full error, body quote and all.
      await expect(fetchListings(config)).rejects.toThrow(/Unexpected token '<'.*<html>/)
    })

    expect(calls).toEqual({ 'listings.fetch.parse': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({ action: 'listings.fetch.parse', attributes: { errName: 'SyntaxError', msg: 'listings body is not JSON' } })
    // FAILURES.md 7.6: no part of a response body is sent.
    expect(JSON.stringify(event)).not.toMatch(/html|Bad Gateway/)
  })

  it('does not report a body read the caller aborted', async () => {
    const controller = new AbortController()
    stubFetch(async () => {
      const res = new Response('{}')
      vi.spyOn(res, 'json').mockImplementation(async () => {
        controller.abort()
        throw new DOMException('This operation was aborted', 'AbortError')
      })
      return res
    })

    await expect(fetchListings(config, { signal: controller.signal })).rejects.toThrow('aborted')
    expect(takeFailureEvents()).toEqual([])
  })

  it('reports JSON null and rejects with the TypeError it always threw', async () => {
    stubFetch(json(null))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchListings(config)).rejects.toThrow(TypeError)
    })

    expect(calls).toEqual({ 'listings.parse.invalid': 1 })
    expect(takeFailureEvents()).toMatchObject([{ action: 'listings.parse.invalid', attributes: { msg: 'no result.rs array' } }])
  })

  // A9 bug fix: a non-array result.rs used to come back as `listings`, and
  // useSellwildListings (React Native) then called .map on it and crashed.
  it('never returns a non-array rs as listings (it gives [])', async () => {
    const body = invalidListingsResponse('rs-not-array')
    expectInvalid('listings-response', body, { instancePath: '/result/rs', keyword: 'type' })
    stubFetch(json(body))

    let result = { listings: undefined as unknown }
    const calls = await countLogFailureCalls(async () => {
      result = await fetchListings(config)
    })

    expect(result.listings).toEqual([])
    expect(calls).toEqual({ 'listings.parse.invalid': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.parse.invalid'])
  })

  it.each([
    ['an envelope without rs', () => listingsResponse({ rs: undefined as never })],
    ['rs that is text', () => listingsResponse({ rs: 'none' as never })],
    // rs wins over listings, so the array beside it is never read.
    ['rs that is text beside a listings array', () => listingsResponse({ rs: 'none' as never, listings: [listing()] })],
    ['result null', () => invalidListingsResponse('result-null')],
    ['a result that is text', () => ({ ...listingsResponse(), result: 'x' as never })],
    ['a JSON string', () => 'text'],
    ['a JSON array', () => [listing()]],
  ])('reports %s once and gives no listings', async (_name, make) => {
    const body = make()
    // Each is a shape the listings-response contract rejects.
    expect(validate('listings-response', body).ok).toBe(false)
    stubFetch(json(body))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchListings(config)).resolves.toMatchObject({ listings: [] })
    })

    expect(calls).toEqual({ 'listings.parse.invalid': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.parse.invalid'])
  })
})

describe('parseListingsResponse and hasListingsArray', () => {
  // rs that is empty text is falsy, so both fall through to result.listings.
  it('reads result.listings when rs is empty text, and both agree there is a list', async () => {
    const body = listingsResponse({ rs: '' as never, listings: [listing()] })
    expectInvalid('listings-response', body, { instancePath: '/result/rs', keyword: 'type' })

    expect(hasListingsArray(body)).toBe(true)
    expect(parseListingsResponse(body).listings).toEqual([listing()])

    clearListingCache()
    stubFetch(json(body))
    await expect(fetchListings(config)).resolves.toMatchObject({ listings: [listing()] })
    expect(takeFailureEvents()).toEqual([])
  })

  it('unwraps result.rs, result.listings or a bare body, and agrees on whether it found a list', () => {
    const rs = listingsResponse({ config: { browse: 1 }, widgetCacheVersionId: '7' })
    expect(parseListingsResponse(rs)).toEqual({ listings: rs.result.rs, config: { browse: 1 }, widgetCacheVersionId: '7' })
    expect(hasListingsArray(rs)).toBe(true)

    const bare = listingsResponse().result
    expect(parseListingsResponse(bare).listings).toBe(bare.rs)
    expect(hasListingsArray(bare)).toBe(true)
  })

  // rs that is non-empty text wins over result.listings, so both see no list.
  it('reads rs, not result.listings, when rs is text, and both agree there is no list', () => {
    const body = listingsResponse({ rs: 'none' as never, listings: [listing()] })
    expectInvalid('listings-response', body, { instancePath: '/result/rs', keyword: 'type' })

    expect(hasListingsArray(body)).toBe(false)
    expect(parseListingsResponse(body).listings).toEqual([])
  })

  it.each(['rs-not-array', 'missing-result', 'result-null'])('finds no list in the invalid fixture %s and gives []', (name) => {
    const body = invalidListingsResponse(name)
    expect(parseListingsResponse(body)).toEqual({ listings: [], config: {}, widgetCacheVersionId: '0' })
    expect(hasListingsArray(body)).toBe(name === 'missing-result')
  })

  it('finds no list in JSON that is not an object, and throws on null as it always has', () => {
    for (const body of ['text', 7, true]) {
      expect(hasListingsArray(body)).toBe(false)
      expect(parseListingsResponse(body).listings).toEqual([])
    }
    expect(hasListingsArray(null)).toBe(false)
    expect(() => parseListingsResponse(null)).toThrow(TypeError)
  })
})

describe('buildTagCacheUrl and parseTagCacheResponse', () => {
  it('puts the encoded keywords and count on the tag-cache URL', () => {
    expect(buildTagCacheUrl('mountain bike & more', 4)).toBe(
      'https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/listings?keywords=mountain%20bike%20%26%20more&count=4&v=1',
    )
  })

  it('throws URIError for keywords that are not well-formed UTF-16, as encodeURIComponent does', () => {
    // A host that cuts a title by length can split an emoji and leave a lone surrogate.
    expect(() => buildTagCacheUrl('trail shoes \uD83D', 2)).toThrow(URIError)
  })

  it('takes the first count items of an array, and null for anything else', () => {
    const items = tagCacheResponse()
    expect(parseTagCacheResponse(items, 2)).toEqual(items.slice(0, 2))
    expect(parseTagCacheResponse(items, 10)).toEqual(items)
    expect(parseTagCacheResponse(listingsResponse(), 2)).toBeNull()
    expect(parseTagCacheResponse(null, 2)).toBeNull()
  })
})

describe('fetchTagCacheListings', () => {
  const TAG_HOST = 'tbd4rmdvjk.execute-api.us-east-1.amazonaws.com'

  it('asks nothing for empty keywords or a zero count', async () => {
    const fetchMock = stubFetch(json(tagCacheResponse()))
    await expect(fetchTagCacheListings({ keywords: '', count: 3 })).resolves.toEqual([])
    await expect(fetchTagCacheListings({ keywords: 'bike', count: 0 })).resolves.toEqual([])
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('returns up to count listings from the tag cache', async () => {
    const fetchMock = stubFetch(json(tagCacheResponse()))
    const controller = new AbortController()

    const items = await fetchTagCacheListings({ keywords: 'mountain bike', count: 2, signal: controller.signal })

    expect(fetchMock).toHaveBeenCalledExactlyOnceWith(
      'https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/listings?keywords=mountain%20bike&count=2&v=1',
      { signal: controller.signal },
    )
    expect(items).toEqual(tagCacheResponse().slice(0, 2))
  })

  it('reports a network error once and gives []', async () => {
    stubFetch(async () => {
      throw new TypeError('Network request failed')
    })

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'bike', count: 2 })).resolves.toEqual([])
    })

    expect(calls).toEqual({ 'listings.tag_cache.network': 1 })
    expect(takeRecordedFailures()).toMatchObject([
      {
        event: {
          action: 'listings.tag_cache.network',
          label: 'listings',
          attributes: { severity: 'warn', errName: 'TypeError', msg: 'Network request failed', host: TAG_HOST },
        },
      },
    ])
  })

  it('reports keywords it cannot URL-encode once, asks nothing and gives [] instead of rejecting', async () => {
    const fetchMock = stubFetch(json(tagCacheResponse()))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'private trail shoes \uD83D', count: 2 })).resolves.toEqual([])
    })

    expect(fetchMock).not.toHaveBeenCalled()
    expect(calls).toEqual({ 'listings.tag_cache_url.invalid': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({
      action: 'listings.tag_cache_url.invalid',
      label: 'listings',
      attributes: { severity: 'error', errName: 'URIError', msg: 'tag cache keywords cannot be URL-encoded', host: TAG_HOST },
    })
    // FAILURES.md 7.6: search keywords are never sent.
    expect(JSON.stringify(event)).not.toMatch(/private|trail|shoes|keywords=/)
  })

  it('never sends the keywords, only the host', async () => {
    stubFetch(async () => {
      throw new TypeError('offline')
    })

    await fetchTagCacheListings({ keywords: 'private search words', count: 2 })

    const [event] = takeFailureEvents()
    expect(JSON.stringify(event)).not.toMatch(/private|search|words|keywords/)
  })

  it('does not report a caller abort, of the request or of the body read', async () => {
    const controller = new AbortController()
    stubFetch(async () => {
      controller.abort()
      throw new DOMException('This operation was aborted', 'AbortError')
    })
    await expect(fetchTagCacheListings({ keywords: 'bike', count: 2, signal: controller.signal })).resolves.toEqual([])

    const second = new AbortController()
    stubFetch(async () => {
      const res = new Response(JSON.stringify(tagCacheResponse()))
      vi.spyOn(res, 'json').mockImplementation(async () => {
        second.abort()
        throw new DOMException('This operation was aborted', 'AbortError')
      })
      return res
    })
    await expect(fetchTagCacheListings({ keywords: 'bike', count: 2, signal: second.signal })).resolves.toEqual([])

    expect(takeFailureEvents()).toEqual([])
  })

  it('reports a non-2xx answer once, and still returns an array body, as it always has', async () => {
    stubFetch(json(tagCacheResponse(), 503))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'bike', count: 1 })).resolves.toEqual(tagCacheResponse().slice(0, 1))
    })

    expect(calls).toEqual({ 'listings.tag_cache.http': 1 })
    expect(takeFailureEvents()).toMatchObject([
      { action: 'listings.tag_cache.http', attributes: { severity: 'error', msg: 'HTTP 503', httpStatus: '503', host: TAG_HOST } },
    ])
  })

  it('reports a 403 XML answer once, as HTTP, and gives []', async () => {
    stubFetch(answer(accessDenied, 403))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'bike', count: 2 })).resolves.toEqual([])
    })

    expect(calls).toEqual({ 'listings.tag_cache.http': 1 })
    expect(takeFailureEvents().map((e) => [e.action, e.attributes.httpStatus])).toEqual([['listings.tag_cache.http', '403']])
  })

  it('reports a non-2xx body that is not an array once, as HTTP', async () => {
    stubFetch(json(listingsResponse(), 500))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'bike', count: 2 })).resolves.toEqual([])
    })

    expect(calls).toEqual({ 'listings.tag_cache.http': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.tag_cache.http'])
  })

  it('reports a 2xx body that is not JSON once, by the error name only, and gives []', async () => {
    stubFetch(answer(accessDenied))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'bike', count: 2 })).resolves.toEqual([])
    })

    expect(calls).toEqual({ 'listings.tag_cache.parse': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({
      action: 'listings.tag_cache.parse',
      attributes: { severity: 'error', errName: 'SyntaxError', msg: 'tag cache body is not JSON', host: TAG_HOST },
    })
    // FAILURES.md 7.6: V8 quotes the start of the body ("<?xml ver"...); none of it is sent.
    expect(JSON.stringify(event)).not.toMatch(/xml|AccessDenied/)
  })

  it('reports a 2xx body that is not an array once and gives []', async () => {
    const body = listingsResponse()
    expectValid('listings-response', body)
    stubFetch(json(body))

    const calls = await countLogFailureCalls(async () => {
      await expect(fetchTagCacheListings({ keywords: 'bike', count: 2 })).resolves.toEqual([])
    })

    expect(calls).toEqual({ 'listings.tag_cache.invalid': 1 })
    expect(takeFailureEvents()).toMatchObject([
      { action: 'listings.tag_cache.invalid', attributes: { severity: 'error', msg: 'tag cache JSON is an object', host: TAG_HOST } },
    ])
  })
})
