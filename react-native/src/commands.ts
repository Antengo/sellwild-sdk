import { NativeModules } from 'react-native'
import type { SellwildGeo } from '@sellwild/sdk-core'

// Imperative bridge to the native Sellwild method module. The ad surface is
// otherwise view-manager-only (config flows as a prop on <SellwildBanner> /
// <SellwildFeed>); this file exposes the session-scoped native setters.
const SellwildRNModule = NativeModules.SellwildRNModule as
  | { setGeo?: (geo: Record<string, unknown>) => void }
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
