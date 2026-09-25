import { describe, expect, it } from 'vitest'
import { invalidListings, listing, listingVariants } from '.'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/factory-checks'

describe('listing factory', () => {
  it('defaults to the first item of the real listings cache', () => {
    const item = listing()
    expect(item).toMatchObject({ id: '105140231', title: '2021 Lexus UX UX 200', shippable: true })
    expectValid('listing', item, 'default')
  })

  it('builds every fixture variant as a valid listing', () => {
    const names = Object.keys(listingVariants)
    expect(names).toEqual(expect.arrayContaining(['cache-sample', 'numeric-id', 'remote-url-null', 'bargainhunter-item']))
    for (const name of names) expectValid('listing', listing({}, name), name)
  })

  it('applies typed overrides and stays valid', () => {
    const item = listing({ id: 7, price: 12, remote_url: null, shippable: 'true' })
    expect(item).toMatchObject({ id: 7, price: 12, remote_url: null })
    expectValid('listing', item, 'overrides')
  })

  it('fails the schema when an override breaks it', () => {
    expectInvalid('listing', listing({ title: 42 as unknown as string }), { instancePath: '/title', keyword: 'type' })
    expectInvalid('listing', listing({ photos: [{ thumb: 'x' } as unknown as { url: string }] }), { instancePath: '/photos/0', keyword: 'required' })
  })

  it('fails the schema for each invalid contract fixture', () => {
    expectInvalidCases('listing', invalidListings())
  })
})
