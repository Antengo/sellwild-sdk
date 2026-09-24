import { describe, expect, it } from 'vitest'
import { buildConfig } from '@sellwild/sdk-core'
import {
  bridgeMessage,
  bridgeMessageVariants,
  defaultBridgeMessageVariant,
  invalidBridgeMessages,
  webViewMessageEvent,
  type BridgeMessageType,
} from '.'
import { buildBannerHtml, buildWidgetHtml } from '../../src/htmlBuilder'
import { expectInvalidCases, expectValid } from '../support/schemas'
import { runBannerPage, runWidgetPage } from '../support/widget-page'

const TYPES = Object.keys(defaultBridgeMessageVariant) as BridgeMessageType[]

describe('bridgeMessage factory', () => {
  it('builds each of the four types from its default fixture, valid against the contract', () => {
    expect(TYPES).toEqual(['LISTING_CLICK', 'AD_IMPRESSION', 'WIDGET_LOADED', 'ERROR'])
    for (const type of TYPES) {
      const message = bridgeMessage(type)
      expect(message.type).toBe(type)
      expect(message).not.toHaveProperty('_synthetic')
      expectValid('bridge-message', message, `factory-${type.toLowerCase().replace('_', '-')}`)
    }
  })

  it('passes the contract for every variant', () => {
    expect(Object.keys(bridgeMessageVariants).length).toBeGreaterThan(TYPES.length)
    for (const name of Object.keys(bridgeMessageVariants)) {
      const { type } = bridgeMessageVariants[name]() as { type: BridgeMessageType }
      expectValid('bridge-message', bridgeMessage(type, {}, name), name)
    }
  })

  it('applies overrides over the variant', () => {
    expect(bridgeMessage('ERROR', { message: 'boom' })).toEqual({ type: 'ERROR', message: 'boom' })
    expect(bridgeMessage('AD_IMPRESSION', { zoneId: 43 })).toEqual({ type: 'AD_IMPRESSION', zoneId: 43 })
    expect(bridgeMessage('LISTING_CLICK', {}, 'listing-click-stub').listing).toMatchObject({ id: '105140231' })
    expectValid('bridge-message', bridgeMessage('AD_IMPRESSION', { zoneId: '280' }), 'factory-ad-impression-override')
  })

  it('refuses a variant of another type, or an unknown one', () => {
    expect(() => bridgeMessage('ERROR', {}, 'widget-loaded')).toThrow(
      "bridge-message variant 'widget-loaded' is WIDGET_LOADED, not ERROR",
    )
    expect(() => bridgeMessage('ERROR', {}, 'nope')).toThrow("no bridge-message variant 'nope'")
  })

  it('wraps a message as the onMessage event, leaving text that is not a message as it is', () => {
    expect(webViewMessageEvent(bridgeMessage('WIDGET_LOADED'))).toEqual({ nativeEvent: { data: '{"type":"WIDGET_LOADED"}' } })
    expect(webViewMessageEvent('not json')).toEqual({ nativeEvent: { data: 'not json' } })
  })

  it('has invalid fixtures that fail for the reason the contract names', () => {
    expectInvalidCases('bridge-message', invalidBridgeMessages())
  })
})

describe('the messages the injected scripts really post', () => {
  it('equal the factory messages and pass the contract', () => {
    const config = buildConfig({ partnerCode: 'weatherbug' })
    const page = runWidgetPage(buildWidgetHtml(config))
    page.openListing('https://sellwild.com/listing/105140231')
    page.loadDom()
    page.scriptError('Uncaught TypeError: Cannot read properties of undefined')
    page.scriptError()
    // buildBannerHtml is not used by any component today; it is the only
    // script that sends AD_IMPRESSION.
    const banner = runBannerPage(buildBannerHtml(config, 43, '300x250'))
    banner.adLoaded()

    const posted = [...page.posted, ...banner.posted].map((data) => JSON.parse(data) as unknown)
    expect(posted).toEqual([
      bridgeMessage('LISTING_CLICK'),
      bridgeMessage('WIDGET_LOADED'),
      bridgeMessage('ERROR'),
      bridgeMessage('ERROR', { message: 'Widget load error' }),
      bridgeMessage('AD_IMPRESSION'),
    ])
    const names = ['listing-click', 'widget-loaded', 'error', 'error-default-message', 'ad-impression']
    posted.forEach((message, i) => expectValid('bridge-message', message, `script-${names[i]}`))
  })
})
