import React from 'react'
import { describe, expect, it, vi } from 'vitest'
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer'
import { SDK_VERSION, setFailureContext, type SellwildListing } from '@sellwild/sdk-core'
import { SellwildWidget, type SellwildWidgetProps } from '../src/SellwildWidget'
import { bridgeMessage, listing, webViewMessageEvent } from './factories'
import { expectValid } from './support/schemas'
import { recordFailures, takeFailureEvents, takeRecordedFailures, TEST_NOW, TEST_UID } from './support/failures'
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
  it('is reported once with the platform error, then handed to onError', () => {
    setFailureContext({ partnerCode: 'weatherbug' })
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    act(() => webView.props.onError(loadError()))

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

  it('is reported with the Android error, which has no domain', () => {
    const onError = vi.fn()
    const { tree, webView } = render({ onError })

    act(() =>
      webView.props.onError(
        loadError({ domain: undefined, code: -2, description: 'net::ERR_NAME_NOT_RESOLVED', url: 'https://widget.sellwild.com/app?x=1' }),
      ),
    )

    const [event] = takeFailureEvents()
    expect(event.attributes).toMatchObject({ msg: '-2: net::ERR_NAME_NOT_RESOLVED', host: 'widget.sellwild.com' })
    expectValid('client-failure-event', event, 'widget-webview-load-android')
    expect(onError).toHaveBeenCalledWith(new Error('net::ERR_NAME_NOT_RESOLVED'))

    act(() => tree.unmount())
  })

  it('is reported with the description alone when the error has no domain or code', () => {
    const { tree, webView } = render()

    act(() => webView.props.onError(loadError({ domain: undefined, code: undefined, description: 'Load failed' })))
    act(() => webView.props.onError(loadError({ domain: null, code: null, description: 'Load failed again' })))
    act(() => webView.props.onError(loadError({ domain: '', code: -6, description: 'net::ERR_CONNECTION_REFUSED' })))

    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual([
      'Load failed',
      'Load failed again',
      '-6: net::ERR_CONNECTION_REFUSED',
    ])

    act(() => tree.unmount())
  })

  it('is reported before onError runs, so a throwing host loses nothing', () => {
    const onError = vi.fn(() => {
      throw new Error('host failed')
    })
    const { tree, webView } = render({ onError })

    // As before this change, the host's error propagates from the handler.
    expect(() => webView.props.onError(loadError())).toThrow('host failed')

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
