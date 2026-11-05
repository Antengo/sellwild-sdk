// debug-log.ts — the SDK's one trace logger (contracts/FAILURES.md section 2).
//
// Every call is a no-op unless debug is on. It is for trace output that is
// not a failure: failures go through logFailure (./failures), which echoes
// its own line when debug is on. This module also holds the debug flag that
// echo reads, so configure() sets it once for both.
//
// React Native uses this module too (it re-exports core).

let enabled = false

/** Turn trace output (and the logFailure debug echo) on or off. Only `true` turns it on. */
export function setDebugLogging(on: boolean): void {
  enabled = on === true
}

export function isDebugLogging(): boolean {
  return enabled
}

/** Print one `[Sellwild]` trace line when debug is on; otherwise do nothing. */
export function debugLog(...args: unknown[]): void {
  if (!enabled) return
  console.log('[Sellwild]', ...args)
}
