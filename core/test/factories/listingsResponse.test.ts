import { describe, expect, it } from 'vitest'
import { invalidListingsResponses, listing, listingsResponse, listingsResponseVariants } from '.'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/factory-checks'

describe('listingsResponse factory', () => {
  it('defaults to the real listings-img-data-sm cache', () => {
    const body = listingsResponse()
    expect(body.result.rs).toHaveLength(10)
    expect(body.result.rs[0].id).toBe('105140231')
    expectValid('listings-response', body, 'default')
  })

  it('builds every sample and fixture variant as a valid response', () => {
    const names = Object.keys(listingsResponseVariants)
    expect(names).toEqual(expect.arrayContaining(['bargainhunter', 'listings-sm', 'empty-rs', 'rpc-envelope']))
    for (const name of names) expectValid('listings-response', listingsResponse({}, name), name)
  })

  it('applies typed overrides to result and stays valid', () => {
    const body = listingsResponse({ rs: [listing(), listing({ id: 2 }, 'numeric-id')], widgetCacheVersionId: '733489' })
    expect(body.result.rs.map((l) => l.id)).toEqual(['105140231', 2])
    expect(body.result.widgetCacheVersionId).toBe('733489')
    expectValid('listings-response', body, 'overrides')
  })

  it('fails the schema when an override breaks it', () => {
    expectInvalid('listings-response', listingsResponse({ rs: 'none' as unknown as [] }), { instancePath: '/result/rs', keyword: 'type' })
    expectInvalid('listings-response', listingsResponse({ rs: [listing({ title: undefined as unknown as string })] }), {
      instancePath: '/result/rs/0',
      keyword: 'required',
    })
  })

  it('fails the schema for each invalid contract fixture', () => {
    expectInvalidCases('listings-response', invalidListingsResponses())
  })
})
