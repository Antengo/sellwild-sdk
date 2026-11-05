import { describe, expect, it } from 'vitest'
import type { SellwildListing } from '@sellwild/sdk-core'
import { listingCardView } from '../src/listingCard'
import type { InvalidCase } from '../../core/test/factories/base'
import { invalidPayload, listing as listingPayload } from './factories'
import { expectInvalid, expectValid } from './support/schemas'

/**
 * An override that breaks the listing contract must break it for the stated
 * reason (null: the listing still passes the contract).
 */
function expectContract(item: SellwildListing, error: InvalidCase['error'] | null): void {
  if (error) expectInvalid('listing', item, error)
  else expectValid('listing', item)
}

// A listing as the caches send it (validated factory), typed as the card takes it.
function listing(overrides: Record<string, unknown> = {}, variant?: string): SellwildListing {
  const value = listingPayload(overrides, variant)
  return value as unknown as SellwildListing
}

const view = (l: SellwildListing) => listingCardView(l, 'en-US')

// NaN is no JSON number, so the contract rejects it as a price type.
const priceType = { instancePath: '/price', keyword: 'type' }

describe('listingCardView: a cached listing', () => {
  it('shows the first photo, the rounded price and the title', () => {
    const cached = listing()
    expectValid('listing', cached)

    expect(view(cached)).toEqual({
      photoUrl: (cached.photos[0] as { url: string }).url,
      price: Number(cached.price).toLocaleString('en-US', { maximumFractionDigits: 0 }),
      strikePrice: null,
      showPrice: true,
      showStrike: false,
      currencySymbol: '$',
      title: cached.title,
      issues: [],
    })
  })

  it('reads a number price and strike price (bargainhunter)', () => {
    const item = listing({}, 'bargainhunter-item')
    expectValid('listing', item)
    const card = view(item)

    expect(card.price).toBe(Number(item.price).toLocaleString('en-US', { maximumFractionDigits: 0 }))
    expect(card.strikePrice).toBe(Number(item.strikePrice).toLocaleString('en-US', { maximumFractionDigits: 0 }))
    expect(card.showStrike).toBe(card.strikePrice !== card.price)
    expect(card.issues).toEqual([])
  })

  const prices: Array<[string, unknown, string | null, boolean, InvalidCase['error'] | null]> = [
    ['numeric text', '19315', '19,315', true, null],
    ['decimal text', '25.49', '25', true, null],
    ['a number', 1250.6, '1,251', true, null],
    ['text zero', '0', '0', false, null],
    ['number zero', 0, null, false, null],
    ['empty text', '', null, false, null],
    ['null', null, null, false, priceType],
    ['absent', undefined, null, false, null],
    // The contract allows any text for a price, so text that is not a number
    // is hidden, as before, and is not an issue.
    ['text that is not a number', 'Call us', null, false, null],
  ]

  it.each(prices)('price as %s', (_name, price, formatted, shown, contractError) => {
    const item = listing({ price: price as string })
    expectContract(item, contractError)
    const card = view(item)
    expect([card.price, card.showPrice, card.issues]).toEqual([formatted, shown, []])
  })

  it('hides a strike price that is not a number, which the contract allows: no issue', () => {
    const item = listing({ price: '100', strikePrice: 'n/a' })
    expectValid('listing', item)
    expect(view(item)).toMatchObject({ price: '100', strikePrice: null, showStrike: false, issues: [] })
  })

  it('shows the strike price only next to a shown, different price', () => {
    expect(view(listing({ price: '100', strikePrice: '150' }))).toMatchObject({ strikePrice: '150', showStrike: true })
    expect(view(listing({ price: '100', strikePrice: '100' }))).toMatchObject({ showStrike: false })
    expect(view(listing({ price: '0', strikePrice: '150' }))).toMatchObject({ showPrice: false, showStrike: false })
  })

  it('cuts a long title to 60 characters plus ...', () => {
    const title = 'x'.repeat(61)
    expect(view(listing({ title })).title).toBe(`${'x'.repeat(60)}...`)
    expect(view(listing({ title: 'x'.repeat(60) })).title).toBe('x'.repeat(60))
  })

  it('shows the placeholder for a listing without photos, which is not an issue', () => {
    const empty = listing({ photos: [] })
    expectValid('listing', empty)
    expect(view(empty)).toMatchObject({ photoUrl: null, issues: [] })
    expect(view(invalidPayload<SellwildListing>('listing', 'missing-photos'))).toMatchObject({ photoUrl: null, issues: [] })
  })

  it('uses the currency symbol of the listing currency', () => {
    expect(view(listing({ currency: 'EUR' })).currencySymbol).toBe('€')
  })
})

describe('listingCardView: what the card cannot show', () => {
  it('hides a boolean price instead of showing $1 (price-boolean fixture)', () => {
    const item = invalidPayload<SellwildListing>('listing', 'price-boolean')
    expect(view(item)).toMatchObject({ price: null, showPrice: false, issues: ['price is a boolean'] })
  })

  // Each override with the contract error it causes (null: the contract
  // allows it, but the card cannot show it).
  const bad: Array<[string, Record<string, unknown>, string[], InvalidCase['error'] | null]> = [
    ['a price list', { price: [5] }, ['price is an array'], priceType],
    ['a price object', { price: { amount: 5 } }, ['price is an object'], priceType],
    ['a NaN price', { price: NaN }, ['price is NaN'], priceType],
    ['photos that are not a list', { photos: 'https://img' }, ['photos is a string'], { instancePath: '/photos', keyword: 'type' }],
    ['a first photo without a url', { photos: [{ background: '#fff' }] }, ['photos[0] url is undefined'], { instancePath: '/photos/0', keyword: 'required' }],
    ['a first photo with an empty url', { photos: [{ url: '' }] }, ['photos[0] url is empty'], null],
    ['a first photo that is null', { photos: [null] }, ['photos[0] url is undefined'], { instancePath: '/photos/0', keyword: 'type' }],
    ['a first photo url that is a number', { photos: [{ url: 7 }] }, ['photos[0] url is a number'], { instancePath: '/photos/0/url', keyword: 'type' }],
  ]

  it.each(bad)('%s', (_name, overrides, issues, contractError) => {
    const item = listing(overrides)
    expectContract(item, contractError)
    const card = view(item)
    expect(card.issues).toEqual(issues)
  })

  it('reports the photo-without-url fixture', () => {
    expect(view(invalidPayload<SellwildListing>('listing', 'photo-without-url'))).toMatchObject({
      photoUrl: null,
      issues: ['photos[0] url is undefined'],
    })
  })
})
