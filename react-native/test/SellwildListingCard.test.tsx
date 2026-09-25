import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import type { SellwildConfig, SellwildListing } from '@sellwild/sdk-core'
import { SellwildListingCard } from '../src/SellwildListingCard'
import { listingCardView } from '../src/listingCard'
import { invalidPayload, listing as listingPayload, sellwildConfig } from './factories'
import { expectInvalid, expectValid } from './support/schemas'
import { countLogFailureCalls, recordFailures, takeFailureEvents } from './support/failures'
import { StyleSheet } from './stubs/react-native'

recordFailures()

function render(element: React.ReactElement): ReactTestRenderer {
  let tree: ReactTestRenderer | undefined
  act(() => {
    tree = create(element)
  })
  return tree!
}

function hosts(tree: ReactTestRenderer, type: string): ReactTestInstance[] {
  return tree.root.findAll((node) => (node.type as unknown) === type)
}

/** The text of each Text element, children joined. */
function texts(tree: ReactTestRenderer): string[] {
  return hosts(tree, 'Text').map((node) => ([] as unknown[]).concat(node.props.children).join(''))
}

// A listing as the caches send it (validated factory), typed as the card takes it.
function listing(overrides: Record<string, unknown> = {}, variant?: string): SellwildListing {
  return listingPayload(overrides, variant) as unknown as SellwildListing
}

function card(item: SellwildListing, config: SellwildConfig = sellwildConfig(), onPress?: (l: SellwildListing) => void) {
  return <SellwildListingCard listing={item} config={config} onPress={onPress} />
}

describe('SellwildListingCard: what it shows', () => {
  it('a cached listing: photo, price badge and title', () => {
    const item = listing()
    expectValid('listing', item)
    const view = listingCardView(item)

    const tree = render(card(item))

    expect(hosts(tree, 'Image')[0].props.source).toEqual({ uri: view.photoUrl })
    expect(texts(tree)).toEqual([`$${view.price}`, item.title])
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('a strike price next to a different price, in the configured colors', () => {
    const config = sellwildConfig({ priceColor: '', colors: ['#295baa'], priceFontColor: '#111111' })
    const tree = render(card(listing({ price: '100', strikePrice: '150' }), config))

    expect(texts(tree)).toEqual(['$150', '$100', expect.any(String)])
    const [badge] = hosts(tree, 'View').filter((v) => StyleSheet.flatten(v.props.style).borderTopLeftRadius === 4)
    expect(StyleSheet.flatten(badge.props.style).backgroundColor).toBe('#295baa')
    expect(StyleSheet.flatten(hosts(tree, 'Text')[0].props.style).color).toBe('#111111')

    act(() => tree.unmount())
  })

  it('the default badge colors when the config has none', () => {
    const config = sellwildConfig({ priceColor: '', colors: undefined as unknown as string[], priceFontColor: '', fontColor: '#eeeeee' })
    const tree = render(card(listing({ price: '100', strikePrice: '150' }), config))

    const [badge] = hosts(tree, 'View').filter((v) => StyleSheet.flatten(v.props.style).borderTopLeftRadius === 4)
    expect(StyleSheet.flatten(badge.props.style).backgroundColor).toBe('#333')
    // Strike price and price both fall back to the font color.
    expect(hosts(tree, 'Text').slice(0, 2).map((t) => StyleSheet.flatten(t.props.style).color)).toEqual(['#eeeeee', '#eeeeee'])

    act(() => tree.unmount())
  })

  it('no badge and a placeholder for a listing without price or photos', () => {
    const tree = render(card(listing({ price: '0', photos: [] })))

    expect(hosts(tree, 'Image')).toHaveLength(0)
    expect(texts(tree)).toHaveLength(1)
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })
})

describe('SellwildListingCard: a tap', () => {
  it('hands the listing to onPress', () => {
    const onPress = vi.fn()
    const item = listing()
    const tree = render(card(item, undefined, onPress))

    act(() => hosts(tree, 'TouchableOpacity')[0].props.onPress())

    expect(onPress).toHaveBeenCalledWith(item)

    act(() => tree.unmount())
  })

  it('does nothing without onPress', () => {
    const tree = render(card(listing()))
    expect(() => act(() => hosts(tree, 'TouchableOpacity')[0].props.onPress())).not.toThrow()
    act(() => tree.unmount())
  })
})

describe('SellwildListingCard: a field it cannot show', () => {
  it('hides the price badge for a boolean price instead of showing $1 (price-boolean fixture)', () => {
    const item = invalidPayload<SellwildListing>('listing', 'price-boolean')
    expect(item.price).toBe(true)

    const tree = render(card(item))

    expect(texts(tree)).toEqual([item.title])
    expect(takeFailureEvents().map((e) => [e.action, e.attributes.msg])).toEqual([['listings.item.invalid', 'price is a boolean']])

    act(() => tree.unmount())
  })

  it('hides a price that is text but not a number, with no report: the contract allows any text', async () => {
    const item = listing({ price: 'Call us' })
    expectValid('listing', item)
    let tree: ReactTestRenderer | undefined

    const counts = await countLogFailureCalls(() => {
      tree = render(card(item))
    })

    expect(counts).toEqual({})
    expect(texts(tree!)).toEqual([item.title])

    act(() => tree!.unmount())
  })

  it('is reported once per issue as listings.item.invalid, and not again on a re-render', async () => {
    // The photo-without-url fixture, with the boolean price of the
    // price-boolean fixture: two values the contract rejects.
    const item = {
      ...invalidPayload<SellwildListing>('listing', 'photo-without-url'),
      price: invalidPayload<SellwildListing>('listing', 'price-boolean').price,
    }
    expectInvalid('listing', item, { instancePath: '/photos/0', keyword: 'required' })
    expectInvalid('listing', item, { instancePath: '/price' })
    let tree: ReactTestRenderer | undefined

    const counts = await countLogFailureCalls(() => {
      tree = render(card(item))
      act(() => tree!.update(card(item, sellwildConfig({ fontSize: 15 }))))
    })

    expect(counts).toEqual({ 'listings.item.invalid': 2 })
    const events = takeFailureEvents()
    expect(events.map((e) => [e.label, e.attributes.severity, e.attributes.msg])).toEqual([
      ['listings', 'warn', 'photos[0] url is undefined'],
      ['listings', 'warn', 'price is a boolean'],
    ])
    for (const event of events) expectValid('client-failure-event', event, 'listing-card-item-invalid')
    // The title is listing text: it is never sent.
    expect(JSON.stringify(events)).not.toContain(item.title)
    expect(hosts(tree!, 'Image')).toHaveLength(0)

    act(() => tree!.unmount())
  })
})
