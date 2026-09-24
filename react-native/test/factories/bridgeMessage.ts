// A WebView bridge message: the JSON the script the SDK injects into the
// widget page posts through ReactNativeWebView, and SellwildWidget's
// onMessage parses. Bases: the contract fixtures. The default for each type
// has the shape the injected script really sends (bridgeMessage.test.ts runs
// that script and checks).

import { fixtureVariants, invalidCases, load, type InvalidCase } from '../../../core/test/factories/base'

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

export const bridgeMessageVariants = fixtureVariants('bridge-message')

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
