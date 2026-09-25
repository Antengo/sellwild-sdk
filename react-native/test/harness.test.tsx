import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import Ajv2020 from 'ajv/dist/2020'
import addFormats from 'ajv-formats'
import { eventQueue } from '@sellwild/sdk-core'
import androidRenderBatch from '../../contracts/fixtures/events-batch/valid/android-render.json'
import appConfigSchema from '../../contracts/schemas/app-config.schema.json'
import clientFailureEventSchema from '../../contracts/schemas/client-failure-event.schema.json'
import eventsBatchSchema from '../../contracts/schemas/events-batch.schema.json'
import localizedListingsConfigSchema from '../../contracts/schemas/localized-listings-config.schema.json'
import rnNativeConfigSchema from '../../contracts/schemas/rn-native-config.schema.json'
import * as coreSource from '../../core/src/index'
import * as sdk from '../src/index'
import { rnGeo } from './factories'
import { takeBlockedNetworkCalls } from './setup'
import { freshModulesRecording, takeFailureCodes } from './support/failures'
import * as rnStub from './stubs/react-native'

// The contract schemas (contracts/schemas) the payloads below must match.
// Same options as contracts/scripts/lib/schemas.mjs.
const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true })
addFormats(ajv)
ajv.addSchema([clientFailureEventSchema, appConfigSchema, localizedListingsConfigSchema])
const validateEventsBatch = ajv.compile(eventsBatchSchema)
const validateNativeConfig = ajv.compile(rnNativeConfigSchema)

function render(element: React.ReactElement): ReactTestRenderer {
  let tree: ReactTestRenderer | undefined
  act(() => {
    tree = create(element)
  })
  return tree!
}

function hosts(tree: ReactTestRenderer, type: string): ReactTestInstance[] {
  return tree.root.findAll((node) => node.type === type)
}

describe('package index', () => {
  it('exports the components, the hook, the native setters and the core re-exports', () => {
    const functions = [
      'SellwildBanner',
      'SellwildFeed',
      'SellwildListingCard',
      'useSellwildListings',
      'setGeo',
      'setExternalUserIds',
      'prewarm',
      'configure',
      'buildConfig',
      'buildConfigWithRemote',
      'currencyToSymbol',
      'fetchRemoteConfig',
      'clearRemoteConfigCache',
    ] as const
    for (const name of functions) {
      expect(sdk[name], name).toBeTypeOf('function')
    }
  })

  it('runs against the core source in this repo, not the published build', () => {
    expect(eventQueue).toBe(coreSource.eventQueue)
    expect(sdk.buildConfig).toBe(coreSource.buildConfig)
  })

  it('stamps events with the react-native platform when the index loads', () => {
    const fetchMock = vi.fn(async (_url: string, _init: RequestInit) => new Response(null, { status: 204 }))
    vi.stubGlobal('fetch', fetchMock)

    // An Android event from the contract fixtures, minus the fields the
    // queue fills in. Its android stamp must give way to react-native.
    const { _synthetic, uid, createdTime, ...event } = androidRenderBatch[0]
    eventQueue.pushNow(event)

    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('https://events.sellwild.com/events/queue')
    const body: unknown = JSON.parse(String(init.body))
    expect(body).toEqual([
      {
        event: 'adRenderSucceeded',
        label: '43',
        attributes: { type: 'react-native', sdkVersion: coreSource.SDK_VERSION, code: 'weatherbug' },
        uid: expect.any(String),
        createdTime: expect.any(Number),
      },
    ])
    expect(validateEventsBatch(body), ajv.errorsText(validateEventsBatch.errors)).toBe(true)
  })
})

describe('network block (contract A8)', () => {
  // A reserved .invalid host (RFC 2606), so a broken blocker cannot reach
  // production.
  const PROBE = 'https://blocked.invalid/listings'

  it('makes fetch reject and records the call', async () => {
    await expect(fetch(PROBE)).rejects.toThrow(`network blocked in tests: ${PROBE}`)
    expect(takeBlockedNetworkCalls()).toEqual([`fetch ${PROBE}`])
  })

  // These two run in order. vi.unstubAllGlobals only undoes vi.stubGlobal,
  // so a plain assignment stays until setup's afterEach reinstalls the
  // blocker.
  it('lets a test assign fetch directly', async () => {
    globalThis.fetch = async () => new Response('assigned')

    await expect(fetch(PROBE).then((r) => r.text())).resolves.toBe('assigned')
  })

  it('puts the blocker back after a test assigns fetch directly', async () => {
    await expect(fetch(PROBE)).rejects.toThrow(`network blocked in tests: ${PROBE}`)
    expect(takeBlockedNetworkCalls()).toEqual([`fetch ${PROBE}`])
  })
})

describe('react-native stubs', () => {
  it('render SellwildBanner through the native view manager', () => {
    const config = sdk.buildConfig({ partnerCode: 'harness' })
    const tree = render(<sdk.SellwildBanner config={config} size="300x250" zoneId={43} />)

    const [banner] = hosts(tree, 'SellwildBannerView')
    expect(banner.props).toMatchObject({
      size: '300x250',
      zoneId: '43',
      adStack: 'both',
      config: expect.objectContaining({ partnerCode: 'harness' }),
      style: [{ width: 300, height: 250 }, undefined],
    })
    // The bridge sends the config as JSON, which drops undefined fields.
    const sent: unknown = JSON.parse(JSON.stringify(banner.props.config))
    expect(validateNativeConfig(sent), ajv.errorsText(validateNativeConfig.errors)).toBe(true)

    act(() => tree.unmount())
  })

  it('render the SellwildBanner dev placeholder when the view manager is missing', async () => {
    // SellwildBanner probes UIManager when its module loads, so change the
    // stub first, then import the component again on a fresh module graph.
    rnStub.setRegisteredViewManagers([])
    rnStub.Platform.OS = 'android'
    // A fresh module graph whose core records failures for the test.
    const { buildConfig } = await freshModulesRecording()
    const { SellwildBanner } = await import('../src/SellwildBanner')

    const tree = render(<SellwildBanner config={buildConfig({ partnerCode: 'harness' })} size="320x50" zoneId="7" />)

    expect(hosts(tree, 'SellwildBannerView')).toHaveLength(0)
    const [text] = hosts(tree, 'Text')
    expect(text.props.children).toEqual(['Sellwild native banner not available on ', 'android', ' (yet)'])
    // The missing view manager is reported (test/SellwildBanner.test.tsx has the details).
    expect(takeFailureCodes()).toEqual(['bridge.native_view.missing'])

    act(() => tree.unmount())
  })

  it('give NativeModules.SellwildRNModule mock methods that the setters call', () => {
    const geo = rnGeo({ lat: 40.7, lon: -74 })
    sdk.setGeo(geo)
    sdk.setGeo(null)

    expect(rnStub.NativeModules.SellwildRNModule?.setGeo.mock.calls).toEqual([[geo], [{}]])
  })
})

describe('stub reset in test/setup.ts', () => {
  // These two run in order. The first changes the stub through a copy of the
  // module made after vi.resetModules(). The second checks that setup's
  // afterEach undid the change for that copy and for this file's own import.
  it('lets a test change the stub through a fresh module copy', async () => {
    vi.resetModules()
    const copy = await import('./stubs/react-native')
    expect(copy).not.toBe(rnStub)
    expect(copy.Platform).toBe(rnStub.Platform)

    copy.setRegisteredViewManagers([])
    copy.Platform.OS = 'android'
    copy.NativeModules.SellwildRNModule = undefined
    Object.assign(copy.Dimensions, { get: () => ({ width: 1, height: 1, scale: 1, fontScale: 1 }), extra: true })

    expect(rnStub.Platform.OS).toBe('android')
    expect(rnStub.UIManager.hasViewManagerConfig('SellwildBannerView')).toBe(false)
  })

  it('undoes that change after the test, in every copy of the module', async () => {
    // The module registry still holds the copy the test above imported.
    const copy = await import('./stubs/react-native')
    for (const rn of [copy, rnStub]) {
      expect(rn.Platform.OS).toBe('ios')
      expect(rn.UIManager.hasViewManagerConfig('SellwildBannerView')).toBe(true)
      expect(rn.UIManager.getViewManagerConfig('SellwildFeedView')).toEqual({ Commands: {} })
      expect(rn.NativeModules.SellwildRNModule?.setGeo).toBeTypeOf('function')
      expect(rn.Dimensions.get('window')).toEqual({ width: 390, height: 844, scale: 3, fontScale: 1 })
      expect(rn.Dimensions).not.toHaveProperty('extra')
    }
  })
})
