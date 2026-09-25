// A WebView bridge message: the JSON the script the SDK injects into the
// widget page posts through ReactNativeWebView, and SellwildWidget's
// onMessage parses. Bases: the contract fixtures. The default for each type
// has the shape the injected script really sends (bridgeMessage.test.ts runs
// that script and checks).

import { fixtureVariants, invalidCases, invalidPayload, load, type InvalidCase, type Variants } from '../../../core/test/factories/base'

export interface ListingClickMessage {
  type: 'LISTING_CLICK'
  url?: string
  listing?: Record<string, unknown>
}

export interface AdImpressionMessage {
  type: 'AD_IMPRESSION'
  zoneId?: string | number
}

export interface WidgetLoadedMessage {
  type: 'WIDGET_LOADED'
}

export interface ErrorMessage {
  type: 'ERROR'
  message?: string
}

export type BridgeMessagePayload = ListingClickMessage | AdImpressionMessage | WidgetLoadedMessage | ErrorMessage
export type BridgeMessageType = BridgeMessagePayload['type']
export type BridgeMessageOf<T extends BridgeMessageType> = Extract<BridgeMessagePayload, { type: T }>

const fixtures = fixtureVariants('bridge-message')

// A LISTING_CLICK fixture without its url: contract-valid (only `type` is
// required) but carrying nothing the SDK can hand to onListingPress.
function withoutUrl(): Record<string, unknown> {
  const { url, ...rest } = fixtures['listing-click-url']() as Record<string, unknown>
  void url
  return rest
}

export const bridgeMessageVariants: Variants = {
  ...fixtures,
  'listing-click-empty': withoutUrl,
}

/** Per type, the fixture shaped like what the injected script sends. */
export const defaultBridgeMessageVariant: Record<BridgeMessageType, string> = {
  LISTING_CLICK: 'listing-click-url',
  AD_IMPRESSION: 'ad-impression-no-zone',
  WIDGET_LOADED: 'widget-loaded',
  ERROR: 'error',
}

/** A message of `type`: the variant (by default the one for the type), then the overrides. */
export function bridgeMessage<T extends BridgeMessageType>(
  type: T,
  overrides: Partial<Omit<BridgeMessageOf<T>, 'type'>> = {},
  variant = defaultBridgeMessageVariant[type],
): BridgeMessageOf<T> {
  const base = load<BridgeMessagePayload>('bridge-message', bridgeMessageVariants, variant)
  if (base.type !== type) throw new Error(`bridge-message variant '${variant}' is ${base.type}, not ${type}`)
  return { ...base, ...overrides } as BridgeMessageOf<T>
}

/** The onMessage event react-native-webview delivers for a posted message. */
export function webViewMessageEvent(message: unknown): { nativeEvent: { data: string } } {
  return { nativeEvent: { data: typeof message === 'string' ? message : JSON.stringify(message) } }
}

export function invalidBridgeMessages(): InvalidCase[] {
  return invalidCases('bridge-message')
}

const fixture = (name: string) => fixtures[name]() as Record<string, unknown>

/**
 * Messages that break the contract in one field, built from a valid fixture
 * (or a contract invalid one) plus that field. bridgeMessage.test.ts checks
 * each fails the schema with `error`. JSON null is one of these: the contract
 * allows no null field.
 */
export const wrongTypedBridgeMessages: Record<string, { value: () => Record<string, unknown>; error: InvalidCase['error'] }> = {
  'type-number': {
    value: () => ({ ...invalidPayload<Record<string, unknown>>('bridge-message', 'missing-type'), type: 5 }),
    error: { instancePath: '/type' },
  },
  'listing-click-listing-text': {
    value: () => ({ ...withoutUrl(), listing: 'https://sellwild.com/listing/105140231' }),
    error: { instancePath: '/listing', keyword: 'type' },
  },
  'listing-click-url-number': {
    value: () => ({ ...withoutUrl(), url: 105140231 }),
    error: { instancePath: '/url', keyword: 'type' },
  },
  'ad-impression-zone-object': {
    value: () => ({ ...fixture('ad-impression-text-zone'), zoneId: { id: '43' } }),
    error: { instancePath: '/zoneId', keyword: 'type' },
  },
  // A good url next to a null listing: the url is still what routes.
  'listing-click-listing-null': {
    value: () => ({ ...fixture('listing-click-url'), listing: null }),
    error: { instancePath: '/listing', keyword: 'type' },
  },
  // A good listing next to a url that is not text: the listing still routes.
  'listing-click-stub-url-number': {
    value: () => ({ ...fixture('listing-click-stub'), url: 105140231 }),
    error: { instancePath: '/url', keyword: 'type' },
  },
  // A null listing and no url: nothing routes.
  'listing-click-only-listing-null': {
    value: () => ({ ...withoutUrl(), listing: null }),
    error: { instancePath: '/listing', keyword: 'type' },
  },
  'ad-impression-zone-null': {
    value: () => ({ ...fixture('ad-impression-text-zone'), zoneId: null }),
    error: { instancePath: '/zoneId', keyword: 'type' },
  },
  'error-message-null': {
    value: () => ({ ...fixture('error'), message: null }),
    error: { instancePath: '/message', keyword: 'type' },
  },
}

/** A wrong-typed message (wrongTypedBridgeMessages), marker dropped. */
export function wrongTypedBridgeMessage(name: string): Record<string, unknown> {
  const entry = wrongTypedBridgeMessages[name]
  if (!entry) throw new Error(`no wrong-typed bridge-message '${name}'`)
  const { _synthetic, ...value } = entry.value()
  void _synthetic
  return value
}

/**
 * Text a WebView could deliver that is no bridge message at all: not JSON, or
 * JSON that is not an object. bridgeMessage.test.ts checks each fails.
 */
export const nonMessageTexts = {
  'not-json': 'not json',
  'json-null': 'null',
  'json-number': '42',
  'json-text': '"WIDGET_LOADED"',
  'json-array': '[{"type":"WIDGET_LOADED"}]',
} as const

export type NonMessageText = keyof typeof nonMessageTexts
