# Sellwild SDK — Prebid Ad-Format Launch Notes

_Last updated: 2026-07-28. Covers the `prebid/native-ad-format` (SDK) +
`cms/mobile-native-toggle` (widget) branch line. This is a working handoff doc —
delete or fold into the PR description once merged._

> **The gate before any of this is real:** the whole branch line is
> **build-unverified**. The shaded Prebid fork isn't resolvable in the dev
> environment, so all fork API is written to Prebid Mobile 3.3.x and marked
> verify-on-build. Nothing renders in-app until the SDK compiles against the
> real fork and ships. See [Build verification](#1-build-verification-the-gate).

---

## Branch & commit state

Both feature branches are **stacked on the video/identity work** (they contain
those commits underneath) and are **local only** except where noted.

### SDK — `prebid/native-ad-format` (base `main`)
```
3957f3c dynamic ad slot sizing via rendered-size callback
fef731c multi-size banner across all stacks (prebid, gam, both)
c4dfebb configurable per-zone native height cap + landscape image request
df06c0a Prebid native ad format (prebidOnly) with remote toggle
69b17f7 video: global VIDEO_ENABLED:false no longer dead-letters per-zone
01b5ee2 rn: bridge setExternalUserIds through SellwildRNModule
2537160 geo passthrough + shared store, pbsDebug flag, RN parity
699cae5 app identity fixes, eids rail, outstream video, banner OMID/MRAID
```
Push state: `origin/prebid/app-identity-eids-video` exists **at `01b5ee2`**
(stale — missing `69b17f7`). `prebid/native-ad-format` is **not pushed**.

### Widget — `cms/mobile-native-toggle` (base `master`)
```
4aca8f7d multi-size banner fields for mobile
15b20aaa native height-cap toggle fields for mobile
7c15b736 native ad-format toggle fields for mobile
4add6400 weatherbug: correct S2S endpoint/account + strip MOBILE_ZID trailing space
84ab9913 weatherbug: enable outstream video (VIDEO_ENABLED)
0cea525c mobile outstream-video + pbsDebug app-config toggles
```
Push state: **not confirmable from dev** (the widget remote embeds `nsp37@` and
the keychain cred is unreadable here); assume not pushed.

---

## What's in this line

| Feature | Toggle / control | Stacks | Notes |
|---|---|---|---|
| App identity, eids rail, banner OMID/MRAID | — | all | `699cae5` |
| Geo passthrough + shared store | `geo` config / `setGeo` | all | `2537160` |
| Outstream video | `VIDEO_ENABLED` / `_BY_ZONE` | prebidOnly renders; both needs GAM line item | dormant by default |
| PBS debug | `PBS_DEBUG` / `pbsDebug` | all | `ext.prebid.debug=1` |
| **Native ad format** | `NATIVE_ENABLED` / `_BY_ZONE` | **prebidOnly only** | assets → default template |
| **Native height cap** | `NATIVE_MAX_HEIGHT` / `_BY_ZONE` | native | defaults to slot height |
| **Multi-size banner** | `BANNER_SIZES` / `_BY_ZONE` | **all three** (GAM solid; Prebid/rendering verify) | fallback fill |
| **Dynamic slot sizing** | automatic (`onAdResize`) | all | RN self-sizes |

### Remote-config keys added (all ride the CDN `remote` passthrough → free on RN)
```
VIDEO_ENABLED, VIDEO_ENABLED_BY_ZONE
NATIVE_ENABLED, NATIVE_ENABLED_BY_ZONE
NATIVE_MAX_HEIGHT, NATIVE_MAX_HEIGHT_BY_ZONE          (dp/pt)
BANNER_SIZES, BANNER_SIZES_BY_ZONE                    (["300x250","320x50"])
PBS_DEBUG
```
All added to the Android `NON_BIDDER_REMOTE_KEYS` deny list so format toggles
don't leak into the `.both` auction ext.

---

## Outstanding tasks

### 1. Build verification (the gate)
- [ ] Compile iOS (SPM / xcodebuild), Android (`gradlew assemble`, JDK17), RN (`tsc`).
- [ ] **Verify the fork symbols** — all isolated for one-file fixes:
  - `SellwildVideo` — `VideoParameters`, `Signals.*`, `AdUnitFormat`.
  - `SellwildNative` — `NativeRequest`/`NativeAdUnit`, asset classes, image/data
    type enums, `NativeAd.create`/`PrebidNativeAd.create`, `registerView` /
    `registerViewList`, event delegate/listener names.
  - `SellwildAdSizes` — `BannerAdUnit.addAdditionalSize`, rendering
    `BannerView.addAdditionalSize`, GMA `NSValueFromGADAdSize`.
  - Earlier: `setGlobalORTBConfig`, `ExternalUserId`, `pbsDebug`.

### 2. Push & PRs (creds are yours — dev env can't push)
```bash
cd <sdk>    && git push -u origin prebid/native-ad-format
cd <widget> && git push -u origin cms/mobile-native-toggle
```
- [ ] Also push the stale video branch tip (`69b17f7`) if keeping it separate.
- [ ] Merge order: **video/identity PR first, then native** (native is stacked).
      If the base PR is squash-merged, rebase native onto `main`/`master` first.
- [ ] If a push 403s from the earlier `gh auth setup-git`:
      `git config --global --unset-all "credential.https://github.com.helper"`.

### 3. Deploy / rollout sequence
- [ ] Deploy widget/CMS (compile + publish) so CDN JSON exposes the new keys.
- [ ] Ship a new SDK version (docs say **1.5+**) — video/native/multi-size are
      inert in the live app until this ships, regardless of CDN flags.

### 4. Native go-live prerequisites
- [ ] **Create a native stored imp** in PBS. WeatherBug's is banner 300×250;
      native sends `imp.native.request` and needs its own configId/`MOBILE_ZID`
      + native-capable bidder params.
- [ ] WeatherBug `NATIVE_ENABLED` is intentionally **OFF** (field added, partner
      not flipped). Flip = one CDN edit, but only after the native stored imp.

### 5. Known gaps / follow-ups
- [ ] **prebidOnly multi-size** reports the primary size to `onAdResize`, not the
      winning smaller creative (the rendering `BannerView` doesn't surface it) —
      so a prebidOnly multi-size fallback won't shrink the RN slot.
- [ ] **Feed ad rows** are not self-sizing (only `<SellwildBanner>` is).
- [ ] Native↔banner multiformat fallback (render whichever wins) — needs a
      branch-on-`mediaType` renderer; deferred.
- [ ] RN geo → per-state listing-cache URL wiring (deferred).

### 6. Likely closeable (verify, then check off)
- [ ] `displaymanagerver` (`prebid-mobile` vs `PrebidMobile`) — concluded low
      consequence.
- [ ] PBS config redeploy (omnidex/zeta/iqx/programmaticX/inmobi) — verified live.

---

## Architecture notes for reviewers

- **Fork API is isolated** in `SellwildVideo`, `SellwildNative`, `SellwildAdSizes`
  (+ the native/size callbacks in `SellwildAdView`). Verify-on-build lives there.
- **Native ≠ video.** Video auto-renders in the fork's `BannerView`; native
  returns raw assets the SDK lays out (`SellwildNativeAdView`) and registers for
  tracking. Native is prebidOnly-only; `.both`/`.gamOnly` fall through to banner.
- **Multi-size:** GAM path (`validAdSizes`/`setAdSizes`) is the solid one that
  delivers fallback fill; the Prebid-bid and prebidOnly `addAdditionalSize` calls
  are verify-on-build.
- **Dynamic sizing:** native reports rendered size (`didRenderWithSize` /
  `onAdResize`); the RN bridge forwards it and `<SellwildBanner>` resizes itself.
  iOS host fills the RN-sized container (no longer hard-pins to the primary size).
- **RN parity is free** for the toggles: they ride the `remote` passthrough and
  render inside the `SellwildAdView` the RN banner already hosts. Only the size
  event needed real bridge work.

## Docs
`PREBID.md` and `docs-site/guide/prebid-server.md` (canonical) carry the Native,
Multi-Size, and Dynamic Slot Sizing sections; `android.md` / `ios.md` have
link-stubs; `react-native.md` documents banner auto-sizing.
