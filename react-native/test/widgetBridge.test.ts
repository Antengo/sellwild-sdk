import { describe, expect, it } from 'vitest'
import {
  bridgeFailureReport,
  decodeWidgetMessage,
  httpErrorReport,
  listingStub,
  loadErrorReport,
  type DecodedWidgetMessage,
} from '../src/widgetBridge'
import {
  bridgeMessage,
  invalidPayload,
  nonMessageTexts,
  wrongTypedBridgeMessage,
  type NonMessageText,
} from './factories'

const text = (message: unknown) => JSON.stringify(message)

describe('decodeWidgetMessage: the messages the injected script sends', () => {
  const cases: Array<[string, unknown, DecodedWidgetMessage]> = [
    ['LISTING_CLICK with a url', bridgeMessage('LISTING_CLICK'), {
      action: { kind: 'listingUrl', url: 'https://sellwild.com/listing/105140231' },
      failure: null,
    }],
    ['AD_IMPRESSION without a zone (the banner page)', bridgeMessage('AD_IMPRESSION'), {
      action: { kind: 'impression', zoneId: undefined as unknown as string },
      failure: null,
    }],
    ['AD_IMPRESSION with a number zone', bridgeMessage('AD_IMPRESSION', {}, 'ad-impression-number-zone'), {
      action: { kind: 'impression', zoneId: 43 },
      failure: null,
    }],
    ['AD_IMPRESSION with a text zone', bridgeMessage('AD_IMPRESSION', {}, 'ad-impression-text-zone'), {
      action: { kind: 'impression', zoneId: '43' },
      failure: null,
    }],
    ['WIDGET_LOADED', bridgeMessage('WIDGET_LOADED'), { action: { kind: 'loaded' }, failure: null }],
    ['ERROR', bridgeMessage('ERROR'), {
      action: { kind: 'scriptError', message: 'Uncaught TypeError: Cannot read properties of undefined' },
      failure: null,
    }],
  ]

  it.each(cases)('%s', (_name, message, expected) => {
    expect(decodeWidgetMessage(text(message))).toEqual(expected)
  })

  it('hands on a listing object when the message carries one (listing-click-stub)', () => {
    const message = bridgeMessage('LISTING_CLICK', {}, 'listing-click-stub')
    expect(decodeWidgetMessage(text(message))).toEqual({
      action: { kind: 'listing', listing: message.listing },
      failure: null,
    })
  })

  it('reads an ERROR without message as a script error without text', () => {
    const { message, ...noMessage } = bridgeMessage('ERROR')
    expect(message).toBeTypeOf('string')
    expect(decodeWidgetMessage(text(noMessage))).toEqual({ action: { kind: 'scriptError', message: undefined }, failure: null })
  })

  it('ignores a field the contract does not know (extra-field fixture): not a failure', () => {
    expect(decodeWidgetMessage(text(invalidPayload('bridge-message', 'extra-field')))).toEqual({
      action: { kind: 'loaded' },
      failure: null,
    })
  })
})

describe('decodeWidgetMessage: what the component cannot use is a failure', () => {
  const texts: Array<[NonMessageText, DecodedWidgetMessage['failure']]> = [
    ['json-null', { code: 'bridge.message.invalid', message: 'message is null' }],
    ['json-number', { code: 'bridge.message.invalid', message: 'message is a number' }],
    ['json-text', { code: 'bridge.message.invalid', message: 'message is a string' }],
    ['json-array', { code: 'bridge.message.invalid', message: 'message is an array' }],
  ]

  it.each(texts)('%s', (name, failure) => {
    expect(decodeWidgetMessage(nonMessageTexts[name])).toEqual({ action: null, failure })
  })

  it('not JSON: bridge.message.parse, with the error cut down to its name', () => {
    const { action, failure } = decodeWidgetMessage(nonMessageTexts['not-json'])
    expect(action).toBeNull()
    expect(failure).toMatchObject({ code: 'bridge.message.parse', message: 'message is not JSON' })
    expect(failure?.error).toBeInstanceOf(Error)
    // The engine's message quotes the text; only the name is kept.
    expect([failure?.error?.name, failure?.error?.message, failure?.error?.stack]).toEqual(['SyntaxError', '', undefined])
  })

  it('no data at all: bridge.message.parse', () => {
    expect(decodeWidgetMessage(undefined).failure?.code).toBe('bridge.message.parse')
  })

  it('no type (missing-type fixture) or a type that is not text: bridge.message.invalid', () => {
    expect(decodeWidgetMessage(text(invalidPayload('bridge-message', 'missing-type')))).toEqual({
      action: null,
      failure: { code: 'bridge.message.invalid', message: 'type is undefined' },
    })
    expect(decodeWidgetMessage(text(wrongTypedBridgeMessage('type-number')))).toEqual({
      action: null,
      failure: { code: 'bridge.message.invalid', message: 'type is a number' },
    })
  })

  it('a type the SDK does not send (unknown-type fixture): bridge.message.unsupported', () => {
    expect(decodeWidgetMessage(text(invalidPayload('bridge-message', 'unknown-type')))).toEqual({
      action: null,
      failure: { code: 'bridge.message.unsupported', message: 'unknown type RESIZE' },
    })
  })

  it('a LISTING_CLICK with neither listing nor url: bridge.message.invalid, nothing to route', () => {
    expect(decodeWidgetMessage(text(bridgeMessage('LISTING_CLICK', {}, 'listing-click-empty')))).toEqual({
      action: null,
      failure: { code: 'bridge.message.invalid', message: 'LISTING_CLICK has no listing and no url' },
    })
    // An empty url is no url.
    expect(decodeWidgetMessage(text(bridgeMessage('LISTING_CLICK', { url: '' }))).failure?.message).toBe(
      'LISTING_CLICK has no listing and no url',
    )
  })
})

describe('decodeWidgetMessage: a wrong-typed field is reported and still routed as before', () => {
  it('LISTING_CLICK listing that is not an object', () => {
    const message = wrongTypedBridgeMessage('listing-click-listing-text')
    expect(decodeWidgetMessage(text(message))).toEqual({
      action: { kind: 'listing', listing: message.listing },
      failure: { code: 'bridge.message.invalid', message: 'LISTING_CLICK listing is a string' },
    })
  })

  it('LISTING_CLICK url that is not text', () => {
    expect(decodeWidgetMessage(text(wrongTypedBridgeMessage('listing-click-url-number')))).toEqual({
      action: { kind: 'listingUrl', url: 105140231 },
      failure: { code: 'bridge.message.invalid', message: 'LISTING_CLICK url is a number' },
    })
  })

  it('AD_IMPRESSION zoneId that is neither text nor a number', () => {
    expect(decodeWidgetMessage(text(wrongTypedBridgeMessage('ad-impression-zone-object')))).toEqual({
      action: { kind: 'impression', zoneId: { id: '43' } },
      failure: { code: 'bridge.message.invalid', message: 'AD_IMPRESSION zoneId is an object' },
    })
  })

  it('ERROR message that is not text (error-message-number fixture)', () => {
    expect(decodeWidgetMessage(text(invalidPayload('bridge-message', 'error-message-number')))).toEqual({
      action: { kind: 'scriptError', message: 500 },
      failure: { code: 'bridge.message.invalid', message: 'ERROR message is a number' },
    })
  })

  // The contract allows no null field, so null is wrong-typed, not absent.
  it.each([
    ['ad-impression-zone-null', { kind: 'impression', zoneId: null }, 'AD_IMPRESSION zoneId is null'],
    ['error-message-null', { kind: 'scriptError', message: null }, 'ERROR message is null'],
    ['listing-click-listing-null', { kind: 'listingUrl', url: 'https://sellwild.com/listing/105140231' }, 'LISTING_CLICK listing is null'],
    ['listing-click-only-listing-null', null, 'LISTING_CLICK listing is null'],
  ])('a null field (%s) is reported as invalid and routed as before', (name, action, message) => {
    expect(decodeWidgetMessage(text(wrongTypedBridgeMessage(name)))).toEqual({
      action,
      failure: { code: 'bridge.message.invalid', message },
    })
  })

  it('checks both LISTING_CLICK fields, whichever one routes', () => {
    const message = wrongTypedBridgeMessage('listing-click-stub-url-number')
    expect(decodeWidgetMessage(text(message))).toEqual({
      action: { kind: 'listing', listing: message.listing },
      failure: { code: 'bridge.message.invalid', message: 'LISTING_CLICK url is a number' },
    })
  })
})

describe('listingStub', () => {
  it('is an empty active listing that carries only the url, as onListingPress always got it', () => {
    expect(listingStub('https://sellwild.com/listing/105140231')).toEqual({
      id: '', status: 'active', title: '',
      text: '', url: 'https://sellwild.com/listing/105140231', categoryId: '', categoryGroupId: '',
      currency: 'USD', price: '', strikePrice: '',
      has_photo: false, photo_count: 0, photos: [],
      createdDate: '', videoUrl: '', shippable: '',
      listingType: '', dataSourceId: '',
      user: { id: '', firstName: '', lastName: '', username: '',
              membershipType: '', trustLevel: '', has_photo: '',
              photos: [], isPhoneVerified: false },
    })
  })
})

describe('the reports the component makes', () => {
  it('bridgeFailureReport: component bridge, severity warn', () => {
    const error = new Error('')
    error.name = 'SyntaxError'
    expect(bridgeFailureReport({ code: 'bridge.message.parse', message: 'message is not JSON', error })).toEqual({
      code: 'bridge.message.parse',
      component: 'bridge',
      severity: 'warn',
      error,
      message: 'message is not JSON',
    })
  })

  it('loadErrorReport: iOS domain and code, Android code only, or neither', () => {
    const base = { url: 'https://widget.sellwild.com/', description: 'The Internet connection appears to be offline.' }
    const report = (extra: object) => loadErrorReport({ ...base, ...extra })
    expect(report({ domain: 'NSURLErrorDomain', code: -1009 })).toEqual({
      code: 'widget.webview_load.network',
      component: 'webview',
      error: base.description,
      message: 'NSURLErrorDomain -1009',
      url: base.url,
    })
    expect(report({ code: -2 }).message).toBe('-2')
    expect(report({ domain: null, code: null }).message).toBe('')
    expect(report({ domain: '', code: -6 }).message).toBe(' -6')
  })

  it('httpErrorReport: status, description and url', () => {
    expect(httpErrorReport({ url: 'https://widget.sellwild.com/app', statusCode: 503, description: 'Service Unavailable' })).toEqual({
      code: 'widget.webview_load.http',
      component: 'webview',
      httpStatus: 503,
      message: 'Service Unavailable',
      url: 'https://widget.sellwild.com/app',
    })
  })
})
