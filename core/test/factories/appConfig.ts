// The CDN app config (GET widget.sellwild.com/app/{CODE}/{SLUG}.json), in its
// CONSTANT_CASE wire form. Default: the real weatherbug config.

import { fixtureVariants, invalidCases, load, sampleVariants, type InvalidCase } from './base'

/** The keys the SDK reads, typed as the schema allows; any other key passes through. */
export interface AppConfigPayload {
  LAYOUT: 'app'
  CODE: string
  NAME: string
  SLUG: string
  basename: string
  MOBILE_ZID: string[]
  MOBILE_ZID_IOS: string[]
  MOBILE_ZID_ANDROID: string[]
  DISPLAY_ZID: string[]
  BIDDERS: Record<string, Record<string, unknown>>
  LISTINGS?: string
  AD_STACK?: string
  AD_STACK_BY_ZONE?: Record<string, string> | ''
  AD_REFRESH_INTERVAL?: number
  IAB_CATS?: string | string[]
  S2S_CONFIG?: string | Record<string, unknown>
  LOCALIZED_LISTINGS?: Record<string, unknown> | string | ''
  EVENTS_ENABLED?: boolean | number | string
  FAILURES_ENABLED?: boolean | number | string
  FAILURES_SAMPLE_RATE?: number | string
  DEBUG?: boolean
  [key: string]: unknown
}

const samples = sampleVariants('app-config')

export const appConfigVariants = {
  weatherbug: samples['weatherbug_weatherbug-weatherbug'],
  antengo: samples['antengo_antengo-sellwild-tv'],
  'weatherbug-local-build': samples['weatherbug_weatherbug-weatherbug.local-build'],
  'antengo-local-build': samples['antengo_antengo-sellwild-tv.local-build'],
  ...fixtureVariants('app-config'),
}

export function appConfig(overrides: Partial<AppConfigPayload> = {}, variant = 'weatherbug'): AppConfigPayload {
  return { ...load<AppConfigPayload>('app-config', appConfigVariants, variant), ...overrides }
}

export function invalidAppConfigs(): InvalidCase[] {
  return invalidCases('app-config')
}
