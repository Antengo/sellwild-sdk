import React from 'react'
import { describe, expect, it } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import { appConfig, bridged, invalidRnNativeConfigs, rnNativeConfig, rnNativeConfigVariants, sellwildConfig } from '.'
import { SellwildBanner } from '../../src/SellwildBanner'
import { SellwildFeed } from '../../src/SellwildFeed'
import { prewarm } from '../../src/commands'
import { toNativeConfig } from '../../src/nativeConfig'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/schemas'
import { NativeModules, Platform } from '../stubs/react-native'

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

describe('rnNativeConfig factory', () => {
  it('is, by default, what toNativeConfig sends for the real weatherbug config', () => {
    const config = rnNativeConfig()
    expect(config).toEqual(bridged(toNativeConfig(sellwildConfig())))
    // The stub platform is iOS, so the iOS app identity.
    expect(config).toMatchObject({
      partnerCode: 'weatherbug',
      appBundleId: '281940292',
      appStoreUrl: 'https://apps.apple.com/us/app/weatherbug-weather-forecast/id281940292',
      remote: { CODE: 'weatherbug', SLUG: 'weatherbug-weatherbug' },
    })
    expect(config).not.toHaveProperty('_synthetic')
    expectValid('rn-native-config', config, 'factory-default')
  })

  it('drops the fields the bridge drops: the undefined ones', () => {
    const raw = toNativeConfig(sellwildConfig())
    const unset = Object.keys(raw).filter((key) => raw[key] === undefined)
    expect(unset.length).toBeGreaterThan(0)
    for (const key of unset) expect(rnNativeConfig(), key).not.toHaveProperty(key)
  })

  it('passes the contract for every variant', () => {
    expect(Object.keys(rnNativeConfigVariants)).toEqual(['banner-weatherbug', 'banner-antengo', 'banner', 'feed', 'minimal'])
    for (const name of Object.keys(rnNativeConfigVariants)) {
      expectValid('rn-native-config', rnNativeConfig({}, name), name)
    }
    expect(rnNativeConfig({}, 'banner-antengo').partnerCode).toBe(appConfig({}, 'antengo').CODE)
  })

  it('resolves the app identity for the current platform', () => {
    Platform.OS = 'android'
    const config = rnNativeConfig()
    expect(config).toMatchObject({
      appBundleId: 'com.aws.android',
      appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',
    })
    expectValid('rn-native-config', config, 'factory-android')
  })

  it('applies overrides last', () => {
    const config = rnNativeConfig({ debug: true, gamTag: '/21824729475/test' }, 'minimal')
    expect(config).toEqual({ partnerCode: 'fixture', debug: true, gamTag: '/21824729475/test' })
    expectValid('rn-native-config', config, 'factory-overrides')
  })

  it('fails the contract for each invalid fixture, and for a broken override', () => {
    expectInvalidCases('rn-native-config', invalidRnNativeConfigs())
    expectInvalid('rn-native-config', rnNativeConfig({ partnerCode: '' }), { instancePath: '/partnerCode', keyword: 'minLength' })
    expectInvalid('rn-native-config', rnNativeConfig({ mobileZids: { a: 1 } }), { instancePath: '/mobileZids', keyword: 'type' })
  })
})

describe('the native config React Native really sends', () => {
  it('from SellwildBanner is the factory default', () => {
    const tree = render(<SellwildBanner config={sellwildConfig()} size="300x250" zoneId={43} />)

    expect(bridged(host(tree, 'SellwildBannerView').props.config)).toEqual(rnNativeConfig())

    act(() => tree.unmount())
  })

  it('from prewarm is the factory default', () => {
    prewarm(sellwildConfig())

    const prewarmMock = NativeModules.SellwildRNModule!.prewarm
    expect(prewarmMock).toHaveBeenCalledOnce()
    expect(bridged(prewarmMock.mock.calls[0][0])).toEqual(rnNativeConfig())
  })

  it('from SellwildFeed passes the contract', () => {
    const tree = render(<SellwildFeed config={sellwildConfig()} />)

    const sent = bridged(host(tree, 'SellwildFeedView').props.config as Record<string, unknown>)
    expect(sent).toMatchObject({
      partnerCode: 'weatherbug',
      slug: 'weatherbug-weatherbug',
      listingsUrl: 'https://cache.sellwild.com/listings-img-data-sm-avif-weatherbug',
      remote: { CODE: 'weatherbug' },
    })
    expectValid('rn-native-config', sent, 'feed-weatherbug')

    act(() => tree.unmount())
  })
})
