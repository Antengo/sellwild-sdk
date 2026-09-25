import type { SellwildListing } from '@sellwild/sdk-core'
import type { LogFailureInput } from './failures'
import { jsonKind, parseErrorName } from './jsonKind'

// Pure decoding for <SellwildWidget> (deprecated WebView surface): the
// messages the widget page posts through window.ReactNativeWebView
// (contracts/schemas/bridge-message.schema.json) and the WebView's load
// events, turned into what the component does and what it reports.
//
// Only the script the SDK injects posts to the bridge (the widget bundle
// never does), so a message this cannot read is a failure. It is reported
// once (bridge.message.*). A message with a field of a type the contract does
// not allow is still routed as before, so the host sees no change, and it is
// reported. JSON null is such a type: the contract allows no null field, so
// null is wrong-typed here, not absent.

/** What the component does with one message. */
export type WidgetAction =
  /** Hand `listing` to onListingPress. */
  | { kind: 'listing'; listing: SellwildListing }
  /** A LISTING_CLICK with only a URL: onListingPress gets a stub holding it. */
  | { kind: 'listingUrl'; url: string }
  | { kind: 'impression'; zoneId: string | number }
  | { kind: 'loaded' }
  /** An in-page script error: report it (unless `failure` did), then onError. */
  | { kind: 'scriptError'; message: string | undefined }

export type BridgeMessageFailureCode = 'bridge.message.parse' | 'bridge.message.invalid' | 'bridge.message.unsupported'

/** A message the component could not use, or used with a wrong-typed field. */
export interface BridgeMessageFailure {
  code: BridgeMessageFailureCode
  /**
   * What is wrong: field names and JSON kinds, never a field's value. The one
   * exception is an unknown `type`, named as it came (as Flutter does), which
   * logFailure sanitizes and cuts to 200 characters.
   */
  message?: string
  /** The parse error, cut down to its name. */
  error?: Error
}

export interface DecodedWidgetMessage {
  action: WidgetAction | null
  failure: BridgeMessageFailure | null
}

function decoded(action: WidgetAction | null, failure: BridgeMessageFailure | null = null): DecodedWidgetMessage {
  return { action, failure }
}

function invalid(message: string): BridgeMessageFailure {
  return { code: 'bridge.message.invalid', message }
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value)

/** Decodes the data of one onMessage event. Never throws. */
export function decodeWidgetMessage(data: unknown): DecodedWidgetMessage {
  let msg: unknown
  try {
    msg = JSON.parse(data as string)
  } catch (error) {
    return decoded(null, { code: 'bridge.message.parse', message: 'message is not JSON', error: parseErrorName(error) })
  }
  if (!isObject(msg)) return decoded(null, invalid(`message is ${jsonKind(msg)}`))
  const type = msg.type
  if (typeof type !== 'string') return decoded(null, invalid(`type is ${jsonKind(type)}`))
  switch (type) {
    case 'LISTING_CLICK':
      return listingClick(msg)
    case 'AD_IMPRESSION': {
      // The banner page sends no zoneId, so undefined reaches the host, as before.
      const zoneId = msg.zoneId as string | number
      const wrong = zoneId !== undefined && typeof zoneId !== 'string' && typeof zoneId !== 'number'
      return decoded({ kind: 'impression', zoneId }, wrong ? invalid(`AD_IMPRESSION zoneId is ${jsonKind(zoneId)}`) : null)
    }
    case 'WIDGET_LOADED':
      return decoded({ kind: 'loaded' })
    case 'ERROR': {
      const message = msg.message as string | undefined
      const wrong = message !== undefined && typeof message !== 'string'
      return decoded({ kind: 'scriptError', message }, wrong ? invalid(`ERROR message is ${jsonKind(message)}`) : null)
    }
    default:
      return decoded(null, { code: 'bridge.message.unsupported', message: `unknown type ${type}` })
  }
}

// The web widget sends a URL via window.open() interception. A full listing
// object is not available at the WebView boundary. The listing is passed if
// somehow present (future compatibility), else the URL. Routing is by
// truthiness, as before. Both fields are checked, whichever one routes; the
// first wrong one is reported.
function listingClick(msg: Record<string, unknown>): DecodedWidgetMessage {
  const { listing, url } = msg
  const wrong =
    listing !== undefined && !isObject(listing)
      ? invalid(`LISTING_CLICK listing is ${jsonKind(listing)}`)
      : url !== undefined && typeof url !== 'string'
        ? invalid(`LISTING_CLICK url is ${jsonKind(url)}`)
        : null
  if (listing) return decoded({ kind: 'listing', listing: listing as SellwildListing }, wrong)
  if (url) return decoded({ kind: 'listingUrl', url: url as string }, wrong)
  return decoded(null, wrong ?? invalid('LISTING_CLICK has no listing and no url'))
}

/** The minimal listing onListingPress gets for a URL-only LISTING_CLICK. */
export function listingStub(url: string): SellwildListing {
  return {
    id: '', status: 'active', title: '',
    text: '', url, categoryId: '', categoryGroupId: '',
    currency: 'USD', price: '', strikePrice: '',
    has_photo: false, photo_count: 0, photos: [],
    createdDate: '', videoUrl: '', shippable: '',
    listingType: '', dataSourceId: '',
    user: { id: '', firstName: '', lastName: '', username: '',
            membershipType: '', trustLevel: '', has_photo: '',
            photos: [], isPhoneVerified: false },
  }
}

/** The report of a bridge message failure (component bridge, warn). */
export function bridgeFailureReport(failure: BridgeMessageFailure): LogFailureInput {
  return {
    code: failure.code,
    component: 'bridge',
    severity: 'warn',
    error: failure.error,
    message: failure.message,
  }
}

/** The fields of react-native-webview's onError nativeEvent the report reads. */
export interface WebViewLoadError {
  url?: string
  domain?: string | null
  code?: number | null
  description?: string
}

/**
 * The report of a WebView page load failure (offline, DNS, TLS, a failed
 * navigation). `message` names the platform error, `NSURLErrorDomain -1009`
 * on iOS or `-2` (WebViewClient.ERROR_HOST_LOOKUP) on Android, which has no
 * domain. Only the host of `url` is sent.
 */
export function loadErrorReport(error: WebViewLoadError): LogFailureInput {
  return {
    code: 'widget.webview_load.network',
    component: 'webview',
    error: error.description,
    message: [error.domain, error.code].filter((part) => part != null).join(' '),
    url: error.url,
  }
}

/** The fields of react-native-webview's onHttpError nativeEvent the report reads. */
export interface WebViewHttpError {
  url?: string
  statusCode?: number
  description?: string
}

/**
 * The report of an HTTP error status (4xx or 5xx) for the WebView's page
 * (react-native-webview onHttpError). Only the status, the host of `url` and
 * the platform's description are sent.
 */
export function httpErrorReport(error: WebViewHttpError): LogFailureInput {
  return {
    code: 'widget.webview_load.http',
    component: 'webview',
    httpStatus: error.statusCode,
    message: error.description,
    url: error.url,
  }
}
