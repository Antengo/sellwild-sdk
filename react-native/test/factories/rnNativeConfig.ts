// The `config` prop React Native hands the native banner and feed views (and
// prewarm), in its bridged form: the bridge carries JSON, which drops
// undefined fields. Default: toNativeConfig over the real weatherbug CDN
// config, as <SellwildBanner> and prewarm() send it on the current
// Platform.OS. The contract fixtures are variants too.

import { toNativeConfig } from '../../src/nativeConfig'
import { appConfig, sellwildConfig } from '../../../core/test/factories'
import { fixtureVariants, invalidCases, load, type InvalidCase } from '../../../core/test/factories/base'

/** The keys the schema allows; the native bridges read what they need. */
export interface RnNativeConfigPayload {
  partnerCode: string
  slug?: string
  appBundleId?: string
  appStoreUrl?: string
  gamTag?: string
  debug?: boolean
  remote?: Record<string, unknown>
  [key: string]: unknown
}

/** What crosses the React Native bridge: the JSON form. */
export function bridged<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T
}

export const rnNativeConfigVariants = {
  'banner-weatherbug': () => bridged(toNativeConfig(sellwildConfig())),
  'banner-antengo': () => bridged(toNativeConfig(sellwildConfig({}, appConfig({}, 'antengo')))),
  ...fixtureVariants('rn-native-config'),
}

export function rnNativeConfig(overrides: Partial<RnNativeConfigPayload> = {}, variant = 'banner-weatherbug'): RnNativeConfigPayload {
  return { ...load<RnNativeConfigPayload>('rn-native-config', rnNativeConfigVariants, variant), ...overrides }
}

export function invalidRnNativeConfigs(): InvalidCase[] {
  return invalidCases('rn-native-config')
}
