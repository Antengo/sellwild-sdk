import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import { buildConfig, type SellwildConfig } from '@sellwild/sdk-core'
import { SellwildFeed, type SellwildFeedProps } from '../src/SellwildFeed'
import { nativeZoneId, nativeZoneIds, toNativeConfig, toNativeFeedConfig } from '../src/nativeConfig'
import { appConfig, bridged, listing, sellwildConfig } from './factories'
import { expectValid } from './support/schemas'
import {
  countLogFailureCallsIn,
  freshModulesRecording,
  recordFailures,
  takeFailureEvents,
} from './support/failures'
import * as rn from './stubs/react-native'

recordFailures()

function render(element: React.ReactElement): ReactTestRenderer {
  let tree: ReactTestRenderer | undefined
  act(() => {
    tree = create(element)
  })
  return tree!
}

function host(tree: ReactTestRenderer, type: string): ReactTestInstance {
  return tree.root.find((node) => node.type === type)
}

function hosts(tree: ReactTestRenderer, type: string): ReactTestInstance[] {
  return tree.root.findAll((node) => node.type === type)
}

function feed(props: Partial<SellwildFeedProps> = {}) {
  return <SellwildFeed config={sellwildConfig()} {...props} />
}

const styleOf = (view: ReactTestInstance) => rn.StyleSheet.flatten(view.props.style)

describe('toNativeFeedConfig', () => {
  it('is the banner payload plus the feed fields, with the same keys the feed always sent', () => {
    const config = sellwildConfig()
    const sent = toNativeFeedConfig(config)

    expect(Object.keys(sent)).toEqual([
      'partnerCode', 'slug', 'appBundleId', 'appStoreUrl', 'geo', 'gamTag', 'debug', 'pbsDebug',
      'adRefreshMax', 'adRefreshMaxMobile', 'adRefreshIntervalMs', 'prebidServer', 'localizedListings',
      'growthCode', 'remote', 'listingsUrl', 'priceColor', 'bannerZid', 'bottomBannerZid', 'mobileBannerZid', 'mobileZids',
    ])
    expect(sent).toMatchObject({ ...toNativeConfig(config), slug: config.slug, listingsUrl: config.listingsUrl })
    // BANNER_ZID is '' in the real config, so core keeps its unset 0, which is
    // not sent (see the zone id cases below).
    expect(config.bannerZid).toBe(0)
    expect(sent.bannerZid).toBeUndefined()
    expectValid('rn-native-config', bridged(sent), 'feed-native-config')
  })

  it('resolves the Android app identity on Android', () => {
    rn.Platform.OS = 'android'
    expect(toNativeFeedConfig(sellwildConfig())).toMatchObject({ appBundleId: 'com.aws.android' })
  })

  // Both native feed bridges read the zone ids as text: Android with
  // ReadableMap.getString, which throws for a number, and iOS with `as? String`,
  // which drops one. A config without remote zone ids (buildConfig, or configure
  // when the CDN fetch failed) holds core's default, the number 0.
  it('sends zone ids as text, never as numbers: the unset 0 is left out', () => {
    const defaults = buildConfig({ partnerCode: 'fixture' })
    expect(defaults.bannerZid).toBe(0)

    const sent = bridged(toNativeFeedConfig(defaults))

    for (const key of ['bannerZid', 'bottomBannerZid', 'mobileBannerZid']) expect(sent, key).not.toHaveProperty(key)
    expect(sent.mobileZids).toEqual([])
    expectValid('rn-native-config', sent, 'feed-defaults')
  })

  it('sends a numeric zone id as its text, and a text zone id as it is', () => {
    const config = sellwildConfig({ bannerZid: 43, bottomBannerZid: '44', mobileBannerZid: '', mobileZids: [45, '46'] })

    const sent = bridged(toNativeFeedConfig(config))

    expect(sent).toMatchObject({ bannerZid: '43', bottomBannerZid: '44', mobileBannerZid: '', mobileZids: ['45', '46'] })
    expectValid('rn-native-config', sent, 'feed-zone-ids')
  })
})

describe('nativeZoneId', () => {
  it.each([
    ['text', '43', '43'],
    ['empty text', '', ''],
    ['a number', 43, '43'],
    ['core\'s unset 0', 0, undefined],
    ['NaN', Number.NaN, undefined],
    ['Infinity', Number.POSITIVE_INFINITY, undefined],
    ['undefined', undefined, undefined],
    ['null', null, undefined],
    ['a boolean', true, undefined],
  ])('%s', (_name, zid, sent) => {
    expect(nativeZoneId(zid)).toBe(sent)
  })

  it('maps a list entry by entry, leaving the unset ones out, and passes anything else as it is', () => {
    expect(nativeZoneIds([45, '46', 0, ''])).toEqual(['45', '46', ''])
    expect(nativeZoneIds(undefined)).toBeUndefined()
    expect(nativeZoneIds('45,46')).toBe('45,46')
  })
})

describe('SellwildFeed: the native view', () => {
  it('fills its parent and scrolls by default', () => {
    const tree = render(feed({ style: { marginTop: 8 } }))
    const view = host(tree, 'SellwildFeedView')

    expect(view.props.scrollEnabled).toBe(true)
    expect(styleOf(view)).toEqual({ flex: 1, marginTop: 8 })
    expect(bridged(view.props.config)).toEqual(bridged(toNativeFeedConfig(sellwildConfig())))
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('sizes itself from the content height when embedded, and reports every size to the host', () => {
    const onContentSizeChange = vi.fn()
    const tree = render(feed({ scrollEnabled: false, onContentSizeChange }))
    const sizeChange = (nativeEvent: unknown) =>
      act(() => host(tree, 'SellwildFeedView').props.onContentSizeChange({ nativeEvent }))

    expect(styleOf(host(tree, 'SellwildFeedView'))).toEqual({})
    sizeChange({ width: 390, height: 1200 })
    expect(styleOf(host(tree, 'SellwildFeedView'))).toEqual({ height: 1200 })
    // A zero or missing height keeps the last one.
    sizeChange({ width: 390, height: 0 })
    sizeChange(undefined)
    expect(styleOf(host(tree, 'SellwildFeedView'))).toEqual({ height: 1200 })

    expect(onContentSizeChange.mock.calls).toEqual([
      [{ width: 390, height: 1200 }],
      [{ width: 390, height: 0 }],
      [{ width: undefined, height: 0 }],
    ])

    act(() => tree.unmount())
  })

  it('does not size a scrolling feed from its content', () => {
    const tree = render(feed())

    act(() => host(tree, 'SellwildFeedView').props.onContentSizeChange({ nativeEvent: { height: 900 } }))

    expect(styleOf(host(tree, 'SellwildFeedView'))).toEqual({ flex: 1 })

    act(() => tree.unmount())
  })

  it('hands each native event to its host callback', () => {
    const callbacks = {
      onLoad: vi.fn(),
      onFeedReady: vi.fn(),
      onListingTap: vi.fn(),
      onAdImpression: vi.fn(),
      onHouseAdImpression: vi.fn(),
      onAdClicked: vi.fn(),
      onError: vi.fn(),
    }
    const tree = render(feed(callbacks))
    const view = host(tree, 'SellwildFeedView')
    const tapped = listing()

    act(() => {
      view.props.onFeedLoaded({ nativeEvent: {} })
      view.props.onFeedReady({ nativeEvent: { listingCount: 10 } })
      view.props.onListingTap({ nativeEvent: { listing: tapped } })
      view.props.onAdImpression({ nativeEvent: { zoneId: '43' } })
      view.props.onHouseAdImpression({ nativeEvent: { zoneId: '44' } })
      view.props.onAdClicked({ nativeEvent: { zoneId: '45' } })
      view.props.onFeedError({ nativeEvent: { message: 'listings fetch failed' } })
    })

    expect(callbacks.onLoad).toHaveBeenCalledOnce()
    expect(callbacks.onFeedReady).toHaveBeenCalledWith(10)
    expect(callbacks.onListingTap).toHaveBeenCalledWith(tapped)
    expect(callbacks.onAdImpression).toHaveBeenCalledWith('43')
    expect(callbacks.onHouseAdImpression).toHaveBeenCalledWith('44')
    expect(callbacks.onAdClicked).toHaveBeenCalledWith('45')
    expect(callbacks.onError).toHaveBeenCalledWith(new Error('listings fetch failed'))
    // Native and core report their own failures (log once).
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('is fine without host callbacks', () => {
    const tree = render(feed())
    const view = host(tree, 'SellwildFeedView')

    expect(() =>
      act(() => {
        view.props.onContentSizeChange({ nativeEvent: { height: 10 } })
        view.props.onFeedLoaded({ nativeEvent: {} })
        view.props.onFeedReady({ nativeEvent: { listingCount: 0 } })
        view.props.onListingTap({ nativeEvent: { listing: listing() } })
        view.props.onAdImpression({ nativeEvent: { zoneId: '43' } })
        view.props.onHouseAdImpression({ nativeEvent: { zoneId: '43' } })
        view.props.onAdClicked({ nativeEvent: { zoneId: '43' } })
        view.props.onFeedError({ nativeEvent: {} })
      }),
    ).not.toThrow()

    act(() => tree.unmount())
  })
})

describe('SellwildFeed: the native view manager is not registered', () => {
  async function loadWithoutViewManager() {
    rn.setRegisteredViewManagers(['SellwildBannerView'])
    const core = await freshModulesRecording()
    const { SellwildFeed: Feed } = await import('../src/SellwildFeed')
    const config: SellwildConfig = core.buildConfig({ partnerCode: 'weatherbug' })
    return { core, Feed, config }
  }

  it('reports bridge.native_view.missing once, however often it renders, with a dev placeholder', async () => {
    const { core, Feed, config } = await loadWithoutViewManager()
    rn.Platform.OS = 'android'
    let tree: ReactTestRenderer | undefined

    const counts = await countLogFailureCallsIn(core, () => {
      tree = render(<Feed config={config} />)
      act(() => tree!.update(<Feed config={config} scrollEnabled={false} />))
    })

    expect(counts).toEqual({ 'bridge.native_view.missing': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({
      action: 'bridge.native_view.missing',
      label: 'feed',
      attributes: { severity: 'error', msg: 'SellwildFeedView is not registered in this build' },
    })
    expectValid('client-failure-event', event, 'feed-native-view-missing')
    expect(hosts(tree!, 'SellwildFeedView')).toHaveLength(0)
    expect(host(tree!, 'Text').props.children).toEqual(['Sellwild native feed not available on ', 'android', ' (yet)'])
    expect(styleOf(hosts(tree!, 'View')[0])).toMatchObject({ backgroundColor: '#FEE2E2' })

    act(() => tree!.unmount())
  })

  it('renders an empty view in a release build', async () => {
    const { Feed, config } = await loadWithoutViewManager()
    ;(globalThis as { __DEV__?: boolean }).__DEV__ = false

    const tree = render(<Feed config={config} style={{ marginTop: 4 }} />)

    expect(hosts(tree, 'Text')).toHaveLength(0)
    expect(styleOf(host(tree, 'View'))).toEqual({ flex: 1, marginTop: 4 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['bridge.native_view.missing'])

    act(() => tree.unmount())
  })
})

describe('SellwildFeed: the config it sends', () => {
  it('carries the partner feed fields of another real config', () => {
    const remote = appConfig({}, 'antengo')
    const tree = render(feed({ config: sellwildConfig({}, remote) }))

    const sent = bridged(host(tree, 'SellwildFeedView').props.config as Record<string, unknown>)
    expect(sent).toMatchObject({ partnerCode: remote.CODE, slug: remote.SLUG })
    expectValid('rn-native-config', sent, 'feed-antengo')

    act(() => tree.unmount())
  })
})
