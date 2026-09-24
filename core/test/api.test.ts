import { beforeEach, describe, expect, it, vi } from 'vitest'
import accessDenied from '../../contracts/samples/localized-listings-response/sports-img-data-sm-webp-zz.403.xml?raw'
import { clearListingCache, fetchListings, fetchTagCacheListings, resolveListingsUrl } from '../src/api'
import { buildConfig, DEFAULT_LISTINGS_URL } from '../src/config'
import { listing, listingsResponse, tagCacheResponse } from './factories'
import { takeFailureEvents } from './support/failures'

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

  it('unwraps result.listings, a bare body, and defaults config and version', async () => {
    stubFetch(json({ result: { listings: [listing()] } }))
    await expect(fetchListings(config)).resolves.toEqual({ listings: [listing()], config: {}, widgetCacheVersionId: '0' })

    clearListingCache()
    stubFetch(json({ rs: [listing()], widgetCacheVersionId: '12' }))
    await expect(fetchListings(config)).resolves.toMatchObject({ listings: [listing()], widgetCacheVersionId: '12' })
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

    await expect(fetchListings(config)).rejects.toBe(offline)
    fetchMock.mockImplementation(json(listingsResponse()))
    await expect(fetchListings(config)).resolves.toMatchObject({ listings: expect.any(Array) })

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

  it('reports a non-2xx answer and still parses a JSON body, as it always has', async () => {
    stubFetch(json(listingsResponse({ rs: [] }), 503))

    await expect(fetchListings(config)).resolves.toMatchObject({ listings: [] })

    expect(takeFailureEvents()).toMatchObject([
      { action: 'listings.fetch.http', attributes: { msg: 'HTTP 503', httpStatus: '503', host: 'cache.sellwild.com' } },
    ])
  })

  it('reports a 403 XML answer once, as HTTP, and rejects with the parse error', async () => {
    stubFetch(answer(accessDenied, 403))

    await expect(fetchListings(config)).rejects.toThrow(SyntaxError)

    expect(takeFailureEvents().map((e) => [e.action, e.attributes.httpStatus])).toEqual([['listings.fetch.http', '403']])
  })

  it('reports a non-2xx JSON body without listings once, as HTTP', async () => {
    stubFetch(json({ message: 'Internal Server Error' }, 500))

    await expect(fetchListings(config)).resolves.toEqual({ listings: [], config: {}, widgetCacheVersionId: '0' })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.http'])
  })

  it('reports a 200 body that is not JSON and rejects with the parse error', async () => {
    stubFetch(answer('<html>502 Bad Gateway</html>'))

    await expect(fetchListings(config)).rejects.toThrow(SyntaxError)

    expect(takeFailureEvents()).toMatchObject([{ action: 'listings.fetch.parse', attributes: { errName: 'SyntaxError' } }])
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

    await expect(fetchListings(config)).rejects.toThrow(TypeError)

    expect(takeFailureEvents()).toMatchObject([{ action: 'listings.parse.invalid', attributes: { msg: 'no result.rs array' } }])
  })

  it.each([
    ['an envelope without rs', { result: { config: {} } }, []],
    ['rs that is not an array', { result: { rs: 'none' } }, 'none'],
    ['a JSON string', 'text', []],
    ['a JSON array', [listing()], []],
    ['a result that is text', { result: 'x' }, []],
  ])('reports %s and returns what it always returned', async (_name, body, listings) => {
    stubFetch(json(body))

    await expect(fetchListings(config)).resolves.toMatchObject({ listings })

    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.parse.invalid'])
  })
})

describe('fetchTagCacheListings', () => {
  it('asks nothing for empty keywords or a zero count', async () => {
    const fetchMock = stubFetch(json(tagCacheResponse()))
    await expect(fetchTagCacheListings({ keywords: '', count: 3 })).resolves.toEqual([])
    await expect(fetchTagCacheListings({ keywords: 'bike', count: 0 })).resolves.toEqual([])
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('returns up to count listings from the tag cache', async () => {
    const fetchMock = stubFetch(json(tagCacheResponse()))

    const items = await fetchTagCacheListings({ keywords: 'mountain bike', count: 2 })

    expect(fetchMock.mock.calls[0][0]).toBe(
      'https://tbd4rmdvjk.execute-api.us-east-1.amazonaws.com/dev/listings?keywords=mountain%20bike&count=2&v=1',
    )
    expect(items).toEqual(tagCacheResponse().slice(0, 2))
  })

  it('returns [] for a body that is not an array, or a failed request', async () => {
    stubFetch(json({ rs: [] }))
    await expect(fetchTagCacheListings({ keywords: 'x', count: 2 })).resolves.toEqual([])

    stubFetch(async () => {
      throw new TypeError('offline')
    })
    await expect(fetchTagCacheListings({ keywords: 'x', count: 2 })).resolves.toEqual([])
  })
})
