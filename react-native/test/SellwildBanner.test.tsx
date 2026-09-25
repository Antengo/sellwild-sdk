import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import type { AdSize, SellwildConfig } from '@sellwild/sdk-core'
import { SellwildBanner, type SellwildBannerProps } from '../src/SellwildBanner'
import { appConfig, rnNativeConfig, sellwildConfig, bridged } from './factories'
import { expectValid } from './support/schemas'
import {
  countLogFailureCalls,
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

const slotOf = (banner: ReactTestInstance) => rn.StyleSheet.flatten(banner.props.style)

function banner(props: Partial<SellwildBannerProps> = {}) {
  return <SellwildBanner config={sellwildConfig()} size="300x250" zoneId={43} {...props} />
}

describe('SellwildBanner: the native view', () => {
  it('gets the native config, size, zone and the ad stack resolved in JS', () => {
    const tree = render(banner({ style: { marginTop: 8 } }))
    const view = host(tree, 'SellwildBannerView')

    expect(bridged(view.props.config)).toEqual(rnNativeConfig())
    expect(view.props).toMatchObject({ size: '300x250', zoneId: '43', adStack: 'prebidOnly' })
    expect(slotOf(view)).toEqual({ width: 300, height: 250, marginTop: 8 })
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('reserves the widest fallback size the config adds for the zone', () => {
    const remote = appConfig({}, 'by-zone-maps-objects')
    expectValid('app-config', remote)
    const tree = render(banner({ config: sellwildConfig({}, remote), size: '320x50', zoneId: '280' }))

    expect(slotOf(host(tree, 'SellwildBannerView'))).toEqual({ width: 320, height: 600 })

    act(() => tree.unmount())
  })

  it('follows the size native renders, and goes back to the baseline for a new placement', () => {
    const tree = render(banner())
    const resize = (nativeEvent: unknown) => act(() => host(tree, 'SellwildBannerView').props.onAdResize({ nativeEvent }))

    resize({ width: 320, height: 50 })
    expect(slotOf(host(tree, 'SellwildBannerView'))).toEqual({ width: 320, height: 50 })
    // An empty or missing size is ignored.
    resize({ width: 0, height: 0 })
    resize(undefined)
    expect(slotOf(host(tree, 'SellwildBannerView'))).toEqual({ width: 320, height: 50 })

    act(() => tree.update(banner({ zoneId: 44 })))
    expect(slotOf(host(tree, 'SellwildBannerView'))).toEqual({ width: 300, height: 250 })

    act(() => tree.unmount())
  })

  it('hands each native event to its host callback', () => {
    const callbacks = { onImpression: vi.fn(), onHouseImpression: vi.fn(), onClick: vi.fn(), onError: vi.fn() }
    const tree = render(banner(callbacks))
    const view = host(tree, 'SellwildBannerView')

    act(() => {
      view.props.onAdLoaded({ nativeEvent: {} })
      view.props.onAdImpression({ nativeEvent: { zoneId: '43' } })
      view.props.onHouseAdImpression({ nativeEvent: { zoneId: '43' } })
      view.props.onHouseAdImpression({})
      view.props.onAdClicked({ nativeEvent: {} })
      view.props.onAdFailed({ nativeEvent: { message: 'No fill' } })
    })

    expect(callbacks.onImpression).toHaveBeenCalledOnce()
    expect(callbacks.onHouseImpression.mock.calls).toEqual([['43'], [undefined]])
    expect(callbacks.onClick).toHaveBeenCalledOnce()
    expect(callbacks.onError).toHaveBeenCalledWith(new Error('No fill'))
    // A native ad failure is the native SDK's to report (log once).
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('is fine without host callbacks', () => {
    const tree = render(banner())
    const view = host(tree, 'SellwildBannerView')

    expect(() =>
      act(() => {
        view.props.onAdImpression({ nativeEvent: {} })
        view.props.onHouseAdImpression({ nativeEvent: { zoneId: '43' } })
        view.props.onAdClicked({ nativeEvent: {} })
        view.props.onAdFailed({ nativeEvent: {} })
      }),
    ).not.toThrow()

    act(() => tree.unmount())
  })
})

describe('SellwildBanner: a size label that is not an AdSize', () => {
  it('renders the slot instead of throwing, and reports ad.size.invalid once per placement', async () => {
    // '320x100' is a real IAB size but not an AdSize; JS callers are not type-checked.
    const size = '320x100' as AdSize
    let tree: ReactTestRenderer | undefined

    const counts = await countLogFailureCalls(() => {
      tree = render(banner({ size }))
      // A re-render of the same placement reports nothing new.
      act(() => tree!.update(banner({ size, style: { marginTop: 4 } })))
    })

    expect(counts).toEqual({ 'ad.size.invalid': 1 })
    const view = host(tree!, 'SellwildBannerView')
    // Native gets the label as before; the slot holds no reserved size.
    expect(view.props.size).toBe('320x100')
    expect(slotOf(view)).toEqual({ width: 0, height: 0, marginTop: 4 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({
      action: 'ad.size.invalid',
      label: 'banner',
      attributes: { severity: 'warn', msg: 'size 320x100 is not an AdSize', zoneId: '43' },
    })
    expectValid('client-failure-event', event, 'banner-ad-size-invalid')

    act(() => tree!.unmount())
  })

  it('reserves the remote fallback sizes for it', () => {
    const remote = appConfig({}, 'banner-sizes-json-text')
    const tree = render(banner({ config: sellwildConfig({}, remote), size: 'toString' as AdSize }))

    expect(slotOf(host(tree, 'SellwildBannerView'))).toEqual({ width: 320, height: 250 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual(['size toString is not an AdSize'])

    act(() => tree.unmount())
  })
})

describe('SellwildBanner: the native view manager is not registered', () => {
  async function loadWithoutViewManager() {
    rn.setRegisteredViewManagers([])
    const core = await freshModulesRecording()
    const { SellwildBanner: Banner } = await import('../src/SellwildBanner')
    const config: SellwildConfig = core.buildConfig({ partnerCode: 'weatherbug' })
    return { core, Banner, config }
  }

  it('reports bridge.native_view.missing once, however often it renders, with a dev placeholder', async () => {
    const { core, Banner, config } = await loadWithoutViewManager()
    let first: ReactTestRenderer | undefined
    let second: ReactTestRenderer | undefined

    const counts = await countLogFailureCallsIn(core, () => {
      first = render(<Banner config={config} size="320x50" zoneId="7" />)
      second = render(<Banner config={config} size="300x250" zoneId="8" />)
    })

    expect(counts).toEqual({ 'bridge.native_view.missing': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({
      action: 'bridge.native_view.missing',
      label: 'banner',
      attributes: { client: 'react-native', severity: 'error', msg: 'SellwildBannerView is not registered in this build' },
    })
    expectValid('client-failure-event', event, 'banner-native-view-missing')
    expect(hosts(first!, 'SellwildBannerView')).toHaveLength(0)
    const [placeholder] = hosts(first!, 'View')
    expect(rn.StyleSheet.flatten(placeholder.props.style)).toMatchObject({ width: 320, height: 50, backgroundColor: '#FEE2E2' })
    expect(host(first!, 'Text').props.children).toEqual(['Sellwild native banner not available on ', 'ios', ' (yet)'])

    act(() => {
      first!.unmount()
      second!.unmount()
    })
  })

  it('still reports a size label that is not an AdSize: each failure once', async () => {
    const { core, Banner, config } = await loadWithoutViewManager()
    let tree: ReactTestRenderer | undefined

    const counts = await countLogFailureCallsIn(core, () => {
      tree = render(<Banner config={config} size={'320x100' as AdSize} zoneId="7" />)
      act(() => tree!.update(<Banner config={config} size={'320x100' as AdSize} zoneId="7" style={{ marginTop: 4 }} />))
    })

    expect(counts).toEqual({ 'ad.size.invalid': 1, 'bridge.native_view.missing': 1 })
    expect(takeFailureEvents().map((e) => [e.action, e.label, e.attributes.msg])).toEqual([
      ['ad.size.invalid', 'banner', 'size 320x100 is not an AdSize'],
      ['bridge.native_view.missing', 'banner', 'SellwildBannerView is not registered in this build'],
    ])
    expect(hosts(tree!, 'SellwildBannerView')).toHaveLength(0)

    act(() => tree!.unmount())
  })

  it('renders an empty slot of the right size in a release build', async () => {
    const { Banner, config } = await loadWithoutViewManager()
    ;(globalThis as { __DEV__?: boolean }).__DEV__ = false

    const tree = render(<Banner config={config} size="300x250" zoneId="7" />)

    expect(hosts(tree, 'Text')).toHaveLength(0)
    expect(rn.StyleSheet.flatten(host(tree, 'View').props.style)).toEqual({ width: 300, height: 250 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['bridge.native_view.missing'])

    act(() => tree.unmount())
  })

  it('is treated as missing when UIManager cannot describe view managers at all', async () => {
    delete (rn.UIManager as { getViewManagerConfig?: unknown }).getViewManagerConfig
    await freshModulesRecording()
    const { SellwildBanner: Banner } = await import('../src/SellwildBanner')

    const tree = render(<Banner config={sellwildConfig()} size="320x50" zoneId="7" />)

    expect(hosts(tree, 'SellwildBannerView')).toHaveLength(0)
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['bridge.native_view.missing'])
    expect(rn.requireNativeComponent).not.toHaveBeenCalled()

    act(() => tree.unmount())
  })
})
