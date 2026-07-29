import { NativeModules } from 'react-native'
import type { SellwildEid, SellwildGeo } from '@sellwild/sdk-core'

// Imperative bridge to the native Sellwild method module. The ad surface is
// otherwise view-manager-only (config flows as a prop on <SellwildBanner> /
// <SellwildFeed>); this file exposes the session-scoped native setters.
const SellwildRNModule = NativeModules.SellwildRNModule as
  | {
      setGeo?: (geo: Record<string, unknown>) => void
      setExternalUserIds?: (eids: SellwildEid[]) => void
    }
  | undefined

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
  SellwildRNModule?.setGeo?.((geo ?? {}) as Record<string, unknown>)
}

/**
 * Set partner-supplied external/extended user IDs, emitted as OpenRTB
 * `user.ext.eids` on every native Prebid auction. Pass `[]` to clear.
 *
 * Re-set on each launch (Prebid Mobile does not persist eids across restarts).
 * No-op if the native module isn't linked.
 */
export function setExternalUserIds(eids: SellwildEid[]): void {
  SellwildRNModule?.setExternalUserIds?.(eids ?? [])
}
