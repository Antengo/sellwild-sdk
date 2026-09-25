import { NativeModules } from 'react-native'
import type { SellwildConfig, SellwildEid, SellwildGeo } from '@sellwild/sdk-core'
import { logFailure } from './failures'
import { toNativeConfig } from './nativeConfig'

// Imperative bridge to the native Sellwild method module. The ad surface is
// otherwise view-manager-only (config flows as a prop on <SellwildBanner> /
// <SellwildFeed>); this file exposes the session-scoped native setters.

interface SellwildRNModuleShape {
  setGeo?: (geo: Record<string, unknown>) => void
  setExternalUserIds?: (eids: SellwildEid[]) => void
  prewarm?: (config: Record<string, unknown>) => void
}

type NativeCommand = keyof SellwildRNModuleShape

const SellwildRNModule = NativeModules.SellwildRNModule as SellwildRNModuleShape | undefined

/**
 * Why `method` of the native module cannot run, or null when it can. Pure:
 * the module is passed in.
 */
export function missingNativeCommand(module: unknown, method: NativeCommand): string | null {
  if (module == null || typeof module !== 'object') return `SellwildRNModule is not linked, so ${method} does nothing`
  if (typeof (module as Record<string, unknown>)[method] !== 'function') {
    return `SellwildRNModule has no ${method} (an older native SDK), so it does nothing`
  }
  return null
}

// Methods already reported: a missing module or method is reported once per
// method per process (bridge.native_module.missing), the first time a host
// calls it. The call stays a no-op, as before.
const reportedMissing = new Set<NativeCommand>()

function callNative<K extends NativeCommand>(method: K, arg: Parameters<NonNullable<SellwildRNModuleShape[K]>>[0]): void {
  const missing = missingNativeCommand(SellwildRNModule, method)
  if (missing === null) {
    const fn = SellwildRNModule![method] as (value: typeof arg) => void
    fn.call(SellwildRNModule, arg)
    return
  }
  if (reportedMissing.has(method)) return
  reportedMissing.add(method)
  logFailure({ code: 'bridge.native_module.missing', component: 'bridge', severity: 'warn', message: missing })
}

/**
 * Set or update partner-supplied geo at runtime (OpenRTB `device.geo`) for
 * native Prebid auctions, and seed the shared native geo store read by other
 * surfaces (e.g. the listings feed). Pass `null` to clear.
 *
 * Prefer `config.geo` for the value known at configure time; use `setGeo` when
 * location resolves or changes mid-session. No-op if the native module isn't
 * linked (e.g. before autolinking, or on an unsupported platform).
 */
export function setGeo(geo: SellwildGeo | null): void {
  // Native maps an empty object to "clear", so send {} for null.
  callNative('setGeo', (geo ?? {}) as Record<string, unknown>)
}

/**
 * Set partner-supplied external/extended user IDs, emitted as OpenRTB
 * `user.ext.eids` on every native Prebid auction. Pass `[]` to clear.
 *
 * Re-set on each launch (Prebid Mobile does not persist eids across restarts).
 * No-op if the native module isn't linked.
 */
export function setExternalUserIds(eids: SellwildEid[]): void {
  callNative('setExternalUserIds', eids ?? [])
}

/**
 * Pre-initialize the native ad stack (Prebid + ad server SDK) before the first
 * `<SellwildBanner>`/`<SellwildFeed>` mounts, so the first impression doesn't
 * incur cold-start init latency and fall back to server-only demand.
 *
 * Optional: mounting an ad view already bootstraps idempotently. Call this at
 * app launch (with the same config you pass to the components) when first-fill
 * on a cold start matters. No-op if the native module isn't linked.
 */
export function prewarm(config: SellwildConfig): void {
  callNative('prewarm', toNativeConfig(config))
}
