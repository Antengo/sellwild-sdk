import { describe, expect, it } from 'vitest'
import { listing, tagCacheResponse } from '.'
import { expectInvalid, expectValid } from '../support/factory-checks'

// The tag cache answers a bare array of listings; each item must pass the
// listing schema (there is no tag-cache schema).
describe('tagCacheResponse factory', () => {
  it('defaults to three listing variants, each a valid listing', () => {
    const items = tagCacheResponse()
    expect(items.map((l) => l.id)).toEqual(['105140231', '90391', 105140234])
    items.forEach((item, i) => expectValid('listing', item, `tag-cache-${i}`))
  })

  it('takes the listings to return', () => {
    const items = tagCacheResponse([listing({ id: 'a' }), listing({ id: 'b' })])
    expect(items.map((l) => l.id)).toEqual(['a', 'b'])
    items.forEach((item) => expectValid('listing', item))
  })

  it('fails the listing schema for a broken item', () => {
    const [item] = tagCacheResponse([listing({ photos: undefined as never })])
    expectInvalid('listing', item, { instancePath: '', keyword: 'required' })
  })
})
