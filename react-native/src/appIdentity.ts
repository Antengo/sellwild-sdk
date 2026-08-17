import { Platform } from 'react-native'
import type { SellwildConfig } from '@sellwild/sdk-core'

/**
 * Resolve per-platform app identity for the native bridge.
 *
 * The CMS may carry OS-specific overrides (`APP_BUNDLE_ID_IOS`/`_ANDROID`,
 * `APP_STORE_URL_IOS`/`_ANDROID`) alongside the shared `APP_BUNDLE_ID` /
 * `APP_STORE_URL`. `core`'s `mapRemoteConfig` maps only the shared
 * (OS-agnostic) keys onto `appBundleId`/`appStoreUrl` and stashes the raw
 * payload on `config.remote`; the platform is only known here on the device,
 * so we resolve the OS-specific value at the bridge boundary — the RN analog
 * of the native `SellwildSDK.apply()` (iOS/Android) and Flutter `dart:io`
 * resolution.
 *
 * Both native bridges (feed + banner) consume `config.appBundleId` /
 * `config.appStoreUrl`, so resolving once here makes both correct without any
 * Kotlin/Swift bridge change.
 *
 * Precedence (matches iOS/Android `apply()` and Flutter): the per-platform CDN
 * value, else the shared `appBundleId`/`appStoreUrl` (which already carries any
 * host override). Backward compatible: no suffixed key = today's behavior.
 */
export function resolveAppIdentity(config: SellwildConfig): {
  appBundleId?: string
  appStoreUrl?: string
} {
  const remote = (config.remote ?? {}) as Record<string, unknown>
  const isAndroid = Platform.OS === 'android'
  const pick = (androidKey: string, iosKey: string): string | undefined => {
    const v = remote[isAndroid ? androidKey : iosKey]
    return typeof v === 'string' && v !== '' ? v : undefined
  }
  return {
    appBundleId:
      pick('APP_BUNDLE_ID_ANDROID', 'APP_BUNDLE_ID_IOS') ?? config.appBundleId,
    appStoreUrl:
      pick('APP_STORE_URL_ANDROID', 'APP_STORE_URL_IOS') ?? config.appStoreUrl,
  }
}
