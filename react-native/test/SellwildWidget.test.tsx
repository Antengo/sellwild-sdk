import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import { SDK_VERSION, setFailureContext, type SellwildListing } from '@sellwild/sdk-core'
import { SellwildWidget, type SellwildWidgetProps } from '../src/SellwildWidget'
import {
  appConfig,
  bridgeMessage,
  invalidPayload,
  listing,
  nonMessageTexts,
  webViewMessageEvent,
  wrongTypedBridgeMessage,
  type NonMessageText,
} from './factories'
import { expectValid } from './support/schemas'
import {
  countLogFailureCalls,
  recordFailures,
  takeFailureEvents,
  takeRecordedFailures,
  TEST_NOW,
  TEST_UID,
} from './support/failures'
import { parseStartTag } from './support/html-tag'
import { runWidgetPage, type WidgetPage } from './support/widget-page'

recordFailures()

interface Rendered {
  tree: ReactTestRenderer
  webView: ReactTestInstance
  /** The script injected into the rendered page, run against a fake window. */
  page: WidgetPage
  /** Deliver everything the page posted so far to the WebView's onMessage. */
  deliver(): void
}

function hosts(tree: ReactTestRenderer, type: string): ReactTestInstance[] {
  return tree.root.findAll((node) => node.type === type)
}

function render(props: Partial<SellwildWidgetProps> = {}): Rendered {
  let tree: ReactTestRenderer | undefined
  act(() => {
    tree = create(<SellwildWidget config={{ partnerCode: 'weatherbug' }} {...props} />)
  })
  const [webView] = hosts(tree!, 'WebView')
  const page = runWidgetPage(webView.props.source.html)
  return {
    tree: tree!,
    webView,
    page,
    deliver() {
      for (const data of page.posted.splice(0)) {
        act(() => webView.props.onMessage({ nativeEvent: { data } }))
      }
    },
  }
}

// The WebView onError event (react-native-webview's WebViewErrorEvent) as iOS
// raises it for an offline device. Android has no `domain`.
function loadError(overrides: Record<string, unknown> = {}) {
  return {
    nativeEvent: {
      url: 'https://widget.sellwild.com/',
      loading: false,
      title: '',
      canGoBack: false,
      canGoForward: false,
      lockIdentifier: 0,
      domain: 'NSURLErrorDomain',
      code: -1009,
      description: 'The Internet connection appears to be offline.',
      ...overrides,
    },
  }
}

// What every React Native failure carries once configure() has set the partner.
const COMMON = { code: 'weatherbug', client: 'react-native', clientVersion: SDK_VERSION, fv: '1' }

describe('SellwildWidget: a script error inside the widget page', () => {
  it('is reported once, sanitized, then handed to onError as it came', () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const onError = vi.fn()
    const { tree, page, deliver } = render({ onError })

    page.scriptError('Uncaught TypeError: x is not a function at https://widget.sellwild.com/partner.js?v=1')
    deliver()

    const [report] = takeRecordedFailures()
    expect(report).toEqual({
      event: {
        event: 'clientFailure',
        action: 'bridge.script.exception',
        label: 'webview',
        attributes: {
          ...COMMON,
          severity: 'error',
          // The URL is cut to its host.
          msg: 'Uncaught TypeError: x is not a function at widget.sellwild.com',
          seq: '1',
          repeat: '1',
        },
        uid: TEST_UID,
        createdTime: TEST_NOW,
      },
      // The first failure of the session is flushed at once.
      flushed: true,
    })
    expectValid('client-failure-event', report.event, 'widget-script-exception')
    expect(onError).toHaveBeenCalledOnce()
    expect(onError.mock.calls[0][0]).toEqual(
      new Error('Uncaught TypeError: x is not a function at https://widget.sellwild.com/partner.js?v=1'),
    )

    act(() => tree.unmount())
  })

  it("is reported with the page's fallback text when the error event has no message", () => {
    const onError = vi.fn()
    const { tree, page, deliver } = render({ onError })

    page.scriptError()
    deliver()

    expect(takeFailureEvents().map((e) => [e.action, e.attributes.msg])).toEqual([
      ['bridge.script.exception', 'Widget load error'],
    ])
    expect(onError).toHaveBeenCalledWith(new Error('Widget load error'))

    act(() => tree.unmount())
  })

  it('is reported without msg when the ERROR message carries none', () => {
    const onError = vi.fn()
    const { tree, webView } = render({ onError })
    const { message, ...noMessage } = bridgeMessage('ERROR')
    expect(message).toBeTypeOf('string')

    act(() => webView.props.onMessage(webViewMessageEvent(noMessage)))

    const [event] = takeFailureEvents()
    expect(event.action).toBe('bridge.script.exception')
    expect(event.attributes).not.toHaveProperty('msg')
    expect(onError).toHaveBeenCalledWith(new Error(''))

    act(() => tree.unmount())
  })

  it('is reported when the host passes no onError', () => {
    const { tree, page, deliver } = render()

    page.scriptError('Script error.')
    deliver()

    expect(takeFailureEvents().map((e) => e.action)).toEqual(['bridge.script.exception'])

    act(() => tree.unmount())
  })

  it('is reported once per message: distinct errors are distinct reports', () => {
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    act(() => webView.props.onMessage(webViewMessageEvent(bridgeMessage('ERROR'))))
    act(() => webView.props.onMessage(webViewMessageEvent(bridgeMessage('ERROR', { message: 'Script error.' }))))

    expect(takeFailureEvents().map((e) => [e.attributes.msg, e.attributes.seq])).toEqual([
      ['Uncaught TypeError: Cannot read properties of undefined', '1'],
      ['Script error.', '2'],
    ])
    expect(onError).toHaveBeenCalledTimes(2)

    act(() => tree.unmount())
  })
})

describe('SellwildWidget: the WebView fails to load its page', () => {
  it('is reported once with the platform error, then handed to onError', async () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    const counts = await countLogFailureCalls(() => act(() => webView.props.onError(loadError())))

    // logFailure ran once: the recorded events alone would hide a second,
    // identical call inside the 60 s dedupe window.
    expect(counts).toEqual({ 'widget.webview_load.network': 1 })
    const [event] = takeFailureEvents()
    expect(event).toEqual({
      event: 'clientFailure',
      action: 'widget.webview_load.network',
      label: 'webview',
      attributes: {
        ...COMMON,
        severity: 'error',
        msg: 'NSURLErrorDomain -1009: The Internet connection appears to be offline.',
        host: 'widget.sellwild.com',
        seq: '1',
        repeat: '1',
      },
      uid: TEST_UID,
      createdTime: TEST_NOW,
    })
    expectValid('client-failure-event', event, 'widget-webview-load-ios')
    expect(onError).toHaveBeenCalledWith(new Error('The Internet connection appears to be offline.'))

    act(() => tree.unmount())
  })

  it('is reported with the Android error, which has no domain', async () => {
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    const counts = await countLogFailureCalls(() =>
      act(() =>
        webView.props.onError(
          loadError({ domain: undefined, code: -2, description: 'net::ERR_NAME_NOT_RESOLVED', url: 'https://widget.sellwild.com/app?x=1' }),
        ),
      ),
    )

    expect(counts).toEqual({ 'widget.webview_load.network': 1 })
    const [event] = takeFailureEvents()
    expect(event.attributes).toMatchObject({ msg: '-2: net::ERR_NAME_NOT_RESOLVED', host: 'widget.sellwild.com' })
    expectValid('client-failure-event', event, 'widget-webview-load-android')
    expect(onError).toHaveBeenCalledWith(new Error('net::ERR_NAME_NOT_RESOLVED'))

    act(() => tree.unmount())
  })

  it('is reported with the description alone when the error has no domain or code', async () => {
    const { tree, webView } = render()

    const counts = await countLogFailureCalls(() => {
      act(() => webView.props.onError(loadError({ domain: undefined, code: undefined, description: 'Load failed' })))
      act(() => webView.props.onError(loadError({ domain: null, code: null, description: 'Load failed again' })))
      act(() => webView.props.onError(loadError({ domain: '', code: -6, description: 'net::ERR_CONNECTION_REFUSED' })))
    })

    // Three load errors, three logFailure calls: once each.
    expect(counts).toEqual({ 'widget.webview_load.network': 3 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual([
      'Load failed',
      'Load failed again',
      '-6: net::ERR_CONNECTION_REFUSED',
    ])

    act(() => tree.unmount())
  })

  it('is reported before onError runs, so a throwing host loses nothing', async () => {
    const onError = vi.fn(() => {
      throw new Error('host failed')
    })
    const { tree, webView } = render({ onError })

    const counts = await countLogFailureCalls(() => {
      // As before this change, the host's error propagates from the handler.
      expect(() => webView.props.onError(loadError())).toThrow('host failed')
    })

    expect(counts).toEqual({ 'widget.webview_load.network': 1 })
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['widget.webview_load.network'])

    act(() => tree.unmount())
  })
})

describe('SellwildWidget: the other bridge messages', () => {
  it('reach their callbacks and report nothing', () => {
    const onListingPress = vi.fn<(listing: SellwildListing) => void>()
    const onAdImpression = vi.fn()
    const onLoad = vi.fn()
    const { tree, webView, page, deliver } = render({ onListingPress, onAdImpression, onLoad })

    page.openListing('https://sellwild.com/listing/105140231')
    page.loadDom()
    deliver()
    const tapped = listing()
    act(() => webView.props.onMessage(webViewMessageEvent(bridgeMessage('LISTING_CLICK', { listing: tapped }))))
    act(() => webView.props.onMessage(webViewMessageEvent(bridgeMessage('AD_IMPRESSION', { zoneId: 43 }))))

    expect(onListingPress).toHaveBeenCalledTimes(2)
    expect(onListingPress.mock.calls[0][0]).toMatchObject({ url: 'https://sellwild.com/listing/105140231', id: '' })
    expect(onListingPress.mock.calls[1][0]).toEqual(tapped)
    expect(onAdImpression).toHaveBeenCalledWith(43)
    expect(onLoad).toHaveBeenCalledOnce()
    expect(hosts(tree, 'ActivityIndicator')).toHaveLength(0)
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })

  it('drop a listing tap quietly when the host passes no onListingPress', () => {
    const { tree, page, deliver } = render()

    page.openListing('https://sellwild.com/listing/105140231')
    deliver()

    // The host chose not to handle taps: not a failure.
    expect(takeFailureEvents()).toEqual([])

    act(() => tree.unmount())
  })
})

describe('SellwildWidget: a message the page should not have sent', () => {
  // Delivers `data` to onMessage and returns how many times logFailure ran, per code.
  async function deliverCounting(webView: ReactTestInstance, data: string) {
    return countLogFailureCalls(() => act(() => webView.props.onMessage({ nativeEvent: { data } })))
  }

  const texts: Array<[NonMessageText, string, string]> = [
    ['not-json', 'bridge.message.parse', 'message is not JSON'],
    ['json-null', 'bridge.message.invalid', 'message is null'],
    ['json-number', 'bridge.message.invalid', 'message is a number'],
    ['json-text', 'bridge.message.invalid', 'message is a string'],
    ['json-array', 'bridge.message.invalid', 'message is an array'],
  ]

  it.each(texts)('%s is reported once as %s and reaches no callback', async (name, code, msg) => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const callbacks = { onListingPress: vi.fn(), onAdImpression: vi.fn(), onLoad: vi.fn(), onError: vi.fn() }
    const { tree, webView } = render(callbacks)

    expect(await deliverCounting(webView, nonMessageTexts[name])).toEqual({ [code]: 1 })

    const [event] = takeFailureEvents()
    expect(event).toMatchObject({ action: code, label: 'bridge', attributes: { ...COMMON, severity: 'warn', msg } })
    if (code === 'bridge.message.parse') expect(event.attributes.errName).toBe('SyntaxError')
    expectValid('client-failure-event', event, `widget-${name}`)
    for (const callback of Object.values(callbacks)) expect(callback).not.toHaveBeenCalled()
    expect(hosts(tree, 'ActivityIndicator')).toHaveLength(1)

    act(() => tree.unmount())
  })

  it('a message without a type or of an unknown type is reported once, and reaches no callback', async () => {
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    const counts = await countLogFailureCalls(() => {
      act(() => webView.props.onMessage(webViewMessageEvent(invalidPayload('bridge-message', 'missing-type'))))
      act(() => webView.props.onMessage(webViewMessageEvent(invalidPayload('bridge-message', 'unknown-type'))))
    })

    expect(counts).toEqual({ 'bridge.message.invalid': 1, 'bridge.message.unsupported': 1 })
    expect(takeFailureEvents().map((e) => [e.action, e.label, e.attributes.severity, e.attributes.msg])).toEqual([
      ['bridge.message.invalid', 'bridge', 'warn', 'type is undefined'],
      ['bridge.message.unsupported', 'bridge', 'warn', 'unknown type RESIZE'],
    ])
    expect(onError).not.toHaveBeenCalled()

    act(() => tree.unmount())
  })

  it('a LISTING_CLICK with nothing to open is reported once and not handed to onListingPress', async () => {
    const onListingPress = vi.fn()
    const { tree, webView } = render({ onListingPress })

    const counts = await deliverCounting(webView, JSON.stringify(bridgeMessage('LISTING_CLICK', {}, 'listing-click-empty')))

    expect(counts).toEqual({ 'bridge.message.invalid': 1 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual(['LISTING_CLICK has no listing and no url'])
    expect(onListingPress).not.toHaveBeenCalled()

    act(() => tree.unmount())
  })

  it('a wrong-typed field is reported once and routed as before', async () => {
    const onListingPress = vi.fn()
    const onAdImpression = vi.fn()
    const { tree, webView } = render({ onListingPress, onAdImpression })
    const listingText = wrongTypedBridgeMessage('listing-click-listing-text')
    const urlNumber = wrongTypedBridgeMessage('listing-click-url-number')
    const zoneObject = wrongTypedBridgeMessage('ad-impression-zone-object')

    const counts = await countLogFailureCalls(() => {
      for (const message of [listingText, urlNumber, zoneObject]) {
        act(() => webView.props.onMessage(webViewMessageEvent(message)))
      }
    })

    expect(counts).toEqual({ 'bridge.message.invalid': 3 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual([
      'LISTING_CLICK listing is a string',
      'LISTING_CLICK url is a number',
      'AD_IMPRESSION zoneId is an object',
    ])
    expect(onListingPress.mock.calls.map(([l]) => (typeof l === 'string' ? l : l.url))).toEqual([listingText.listing, urlNumber.url])
    expect(onAdImpression).toHaveBeenCalledWith(zoneObject.zoneId)

    act(() => tree.unmount())
  })

  it('an ERROR whose message is not text is reported once, as invalid, and still reaches onError', async () => {
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    const counts = await deliverCounting(webView, JSON.stringify(invalidPayload('bridge-message', 'error-message-number')))

    expect(counts).toEqual({ 'bridge.message.invalid': 1 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual(['ERROR message is a number'])
    expect(onError).toHaveBeenCalledWith(new Error('500'))

    act(() => tree.unmount())
  })

  it('a null field is reported once, as invalid, and routed as before', async () => {
    const callbacks = { onListingPress: vi.fn(), onAdImpression: vi.fn(), onError: vi.fn() }
    const { tree, webView } = render(callbacks)
    const names = ['listing-click-listing-null', 'listing-click-only-listing-null', 'ad-impression-zone-null', 'error-message-null']

    const counts = await countLogFailureCalls(() => {
      for (const name of names) act(() => webView.props.onMessage(webViewMessageEvent(wrongTypedBridgeMessage(name))))
    })

    // Not bridge.script.exception too: the ERROR is reported once, as invalid.
    expect(counts).toEqual({ 'bridge.message.invalid': 4 })
    // The second listing report has the first one's dedupe key, so core folds
    // it in (FAILURES.md 5.6): three events.
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual([
      'LISTING_CLICK listing is null',
      'AD_IMPRESSION zoneId is null',
      'ERROR message is null',
    ])
    expect(callbacks.onListingPress.mock.calls.map(([l]) => l.url)).toEqual(['https://sellwild.com/listing/105140231'])
    expect(callbacks.onAdImpression.mock.calls).toEqual([[null]])
    // new Error(null), as before: the injected script never sends null.
    expect(callbacks.onError.mock.calls).toEqual([[new Error('null')]])

    act(() => tree.unmount())
  })

  it('a field the contract does not know is ignored: no report', async () => {
    const onLoad = vi.fn()
    const { tree, webView } = render({ onLoad })

    expect(await deliverCounting(webView, JSON.stringify(invalidPayload('bridge-message', 'extra-field')))).toEqual({})

    expect(onLoad).toHaveBeenCalledOnce()
    expect(hosts(tree, 'ActivityIndicator')).toHaveLength(0)

    act(() => tree.unmount())
  })
})

describe('SellwildWidget: a host callback that throws', () => {
  it('is reported once per call and not rethrown, and the page state still changes', async () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const boom = (name: string) => vi.fn(() => {
      throw new TypeError(`${name} failed`)
    })
    const callbacks = {
      onListingPress: boom('onListingPress'),
      onAdImpression: boom('onAdImpression'),
      onLoad: boom('onLoad'),
      onError: boom('onError'),
    }
    const { tree, webView, page } = render(callbacks)

    const counts = await countLogFailureCalls(() => {
      page.openListing('https://sellwild.com/listing/105140231')
      page.loadDom()
      page.scriptError('Script error.')
      for (const data of page.posted.splice(0)) {
        // Not rethrown: the old catch-all swallowed these too.
        expect(() => act(() => webView.props.onMessage({ nativeEvent: { data } }))).not.toThrow()
      }
      act(() => webView.props.onMessage(webViewMessageEvent(bridgeMessage('LISTING_CLICK', { listing: listing() }))))
      act(() => webView.props.onMessage(webViewMessageEvent(bridgeMessage('AD_IMPRESSION', { zoneId: 43 }))))
    })

    expect(counts).toEqual({ 'widget.host_callback.exception': 5, 'bridge.script.exception': 1 })
    const events = takeFailureEvents()
    expect(events.map((e) => [e.action, e.label, e.attributes.severity, e.attributes.errName, e.attributes.msg])).toEqual([
      ['widget.host_callback.exception', 'webview', 'warn', 'TypeError', 'onListingPress threw: onListingPress failed'],
      ['widget.host_callback.exception', 'webview', 'warn', 'TypeError', 'onLoad threw: onLoad failed'],
      ['bridge.script.exception', 'webview', 'error', undefined, 'Script error.'],
      ['widget.host_callback.exception', 'webview', 'warn', 'TypeError', 'onError threw: onError failed'],
      ['widget.host_callback.exception', 'webview', 'warn', 'TypeError', 'onAdImpression threw: onAdImpression failed'],
    ])
    // The same callback failing the same way within a minute is folded
    // into the first report (core dedupe): 5 calls, 4 events.
    for (const event of events) expectValid('client-failure-event', event, 'widget-host-callback')
    expect(hosts(tree, 'ActivityIndicator')).toHaveLength(0)
    for (const callback of Object.values(callbacks)) expect(callback).toHaveBeenCalled()

    act(() => tree.unmount())
  })
})

describe('SellwildWidget: an HTTP error status for the page', () => {
  it('is reported once with the status and host, and onError is not called', async () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    const counts = await countLogFailureCalls(() =>
      act(() =>
        webView.props.onHttpError({
          nativeEvent: { ...loadError().nativeEvent, url: 'https://widget.sellwild.com/app?x=1', statusCode: 503, description: 'Service Unavailable' },
        }),
      ),
    )

    expect(counts).toEqual({ 'widget.webview_load.http': 1 })
    const [event] = takeFailureEvents()
    expect(event).toEqual({
      event: 'clientFailure',
      action: 'widget.webview_load.http',
      label: 'webview',
      attributes: { ...COMMON, severity: 'error', msg: 'Service Unavailable', httpStatus: '503', host: 'widget.sellwild.com', seq: '1', repeat: '1' },
      uid: TEST_UID,
      createdTime: TEST_NOW,
    })
    expectValid('client-failure-event', event, 'widget-webview-load-http')
    expect(onError).not.toHaveBeenCalled()

    act(() => tree.unmount())
  })
})

describe('SellwildWidget: the rendered page', () => {
  it('keeps the same page across parent re-renders with the same config', () => {
    let tree: ReactTestRenderer | undefined
    act(() => {
      tree = create(<SellwildWidget config={{ partnerCode: 'weatherbug' }} />)
    })
    const first = hosts(tree!, 'WebView')[0].props.source.html
    act(() => tree!.update(<SellwildWidget config={{ partnerCode: 'weatherbug' }} style={{ height: 400 }} />))
    expect(hosts(tree!, 'WebView')[0].props.source.html).toBe(first)
    act(() => tree!.update(<SellwildWidget config={{ partnerCode: 'antengo' }} />))
    expect(hosts(tree!, 'WebView')[0].props.source.html).toContain('partner-code="antengo"')

    act(() => tree!.unmount())
  })
})

describe('SellwildWidget: a remote key that cannot be an attribute name', () => {
  it('is left out of the page and reported once for the config', async () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    // Valid under app-config.schema.json, which allows any key.
    const remote = appConfig({ 'NEW KEY': 'a', 'X>Y': 'b' })
    expectValid('app-config', remote)
    let tree: ReactTestRenderer | undefined
    const counts = await countLogFailureCalls(() =>
      act(() => {
        tree = create(<SellwildWidget config={{ partnerCode: 'weatherbug', remote }} />)
      }),
    )

    expect(counts).toEqual({ 'config.field.invalid': 1 })
    const [event] = takeFailureEvents()
    expect(event).toMatchObject({
      action: 'config.field.invalid',
      label: 'webview',
      // The count only: a key is CMS data, so it is not sent.
      attributes: { ...COMMON, severity: 'warn', msg: 'remote keys that cannot be widget attribute names were left out: 2' },
    })
    expectValid('client-failure-event', event, 'widget-remote-key-invalid')
    const tag = parseStartTag(hosts(tree!, 'WebView')[0].props.source.html, 'sellwild-widget')
    expect(tag.attributes.has('new')).toBe(false)
    expect(tag.attributes.has('x')).toBe(false)

    // A parent re-render with the same config does not report it again.
    const again = await countLogFailureCalls(() =>
      act(() => tree!.update(<SellwildWidget config={{ partnerCode: 'weatherbug', remote }} style={{ height: 400 }} />)),
    )
    expect(again).toEqual({})

    act(() => tree!.unmount())
  })

  it('reports nothing for the real weatherbug config', async () => {
    let tree: ReactTestRenderer | undefined
    const counts = await countLogFailureCalls(() =>
      act(() => {
        tree = create(<SellwildWidget config={{ partnerCode: 'weatherbug', remote: appConfig() }} />)
      }),
    )
    expect(counts).toEqual({})
    act(() => tree!.unmount())
  })
})
