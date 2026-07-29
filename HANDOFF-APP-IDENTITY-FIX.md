# Handoff — iOS app identity + app.publisher.id fixes (build-unverified)

Status: **code applied, NOT build-verified.** Requires the iOS sim / Android emulator
loop (see `.claude/skills/native-first-mobile`) and a live-request inspection before
publishing or before retiring any edge-Lambda rewrite.

## What changed

`ios/Sources/SellwildSDK/SellwildPrebidMobile.swift`
- `app.bundle` now set to the **numeric App Store ID** via `Targeting.shared.itunesID`,
  derived from `config.appStoreUrl` (`appStoreId(from:)`, regex `/id\d+`). Falls back to
  Prebid's default (reverse-DNS) if no store URL is parseable.
- Removed `Targeting.shared.sourceapp = appBundleId` — `sourceapp` maps to **app.name**,
  so that line was polluting `app.name` with the reverse-DNS bundle. `app.name` now
  reverts to Prebid's auto-detected display name.
- `app.publisher.id` injected via `Targeting.shared.setGlobalORTBConfig(...)`.
- Earlier same-session fix: `storeURL` moved out of the `appBundleId` guard so a
  configured store URL is never dropped when the bundle id is nil.

`android/src/main/kotlin/com/sellwild/sdk/SellwildAdView.kt`
- Cold-start fix: the first `load()` no longer silently drops to GAM-only while Prebid
  Mobile's async init is still running. Bounded wait (8 × 150ms) then GAM fallback.

`android/src/main/kotlin/com/sellwild/sdk/SellwildPrebidMobile.kt`
- `app.publisher.id` injected via `TargetingParams.setGlobalOrtbConfig(...)`.
- No bundle change — Android's reverse-DNS package name IS the correct `app.bundle`.

## CDN dependency (BLOCKS the publisher.id fix)

`app.publisher.id` is sourced from the CDN `S2S_CONFIG` blob, key `publisherId` (or
`sellerId`). This must equal the **sellers.json seller id** (== schain sid).
- WeatherBug: `S2S_CONFIG.publisherId = "123"`.
- Until the CDN delivers it, the injection is a clean no-op (no regression; the edge
  Lambda still rewrites publisher.id server-side).

## Build-verification checklist (do before publish / before retiring Lambda rewrites)

1. Build the SDK and confirm these symbols resolve in the shaded Prebid fork (all
   standard Prebid Mobile 3.x; the fork is a class/module rename, so they should):
   `Targeting.itunesID`, `Targeting.setGlobalORTBConfig`,
   `TargetingParams.setGlobalOrtbConfig`.
2. Run a real auction on a booted sim/emulator (`debug=1`) and inspect the resolved
   request:
   - `app.bundle` == `281940292` (numeric)
   - `app.name` == `WeatherBug` (NOT the bundle)
   - `app.publisher.id` == `123`  ← only if CDN S2S_CONFIG carries it
   - `imp.ext.skadn.sourceapp` — check whether it followed the bundle to numeric
3. **Protected-fields risk:** confirm `app.publisher.id` actually appears on the wire.
   Prebid docs warn app first-party data MAY be protected from the global-ORTB merge.
   If it's stripped, the SDK injection does nothing — keep the Lambda.

## Do NOT retire these edge-Lambda rewrites until confirmed on the wire

- `app.bundle` reverse-DNS → numeric
- `imp.ext.skadn.sourceapp` reverse-DNS → numeric
- `app.publisher.id` → 123

Retire each only after the corresponding SDK value is observed in a live resolved
request across a build.
