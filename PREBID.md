# Prebid Integration Guide

The Sellwild SDK bids natively. On iOS, Android, and React Native every ad runs through **Mode C (native Prebid Mobile + Google Mobile Ads)** — bundled, no wiring required. **Mode B (Prebid Server S2S)** describes where that auction resolves: Prebid Mobile sends one OpenRTB request to Prebid Server, which fans out to the configured bidders.

The former Mode A (Prebid.js in a WebView) is gone. The WebView widget that hosted it (`SellwildWidgetView` / `SellwildWidget`) has been removed from iOS, Android, and React Native.

---

## Modes at a Glance

| Mode | Where Bidding Runs | IDFA/GAID | 3rd-party Cookies | Extra Dependency |
|------|--------------------|-----------|-------------------|------------------|
| **B — Prebid Server S2S** | Prebid Server (server-side) | via Mode C | N/A (server call) | Self-hosted or managed Prebid Server |
| **C — Prebid Mobile SDK** *(default and only mobile path: iOS/Android/RN)* | Native SDK → Prebid Server | ✓ (with ATT) | N/A | Bundled — no extra dependency |

The SDK sets the OpenRTB `app` context (`bundle`, `storeurl`, `publisher.id`) natively so DSPs receive correct in-app traffic signals.

**Required fields for proper in-app signals:**

```swift
// iOS
c.appBundleId = Bundle.main.bundleIdentifier   // e.g. "com.mycompany.myapp"
c.appStoreUrl = "https://apps.apple.com/app/idXXXXXXXXX"
```

```kotlin
// Android
val config = SellwildConfig(
    appBundleId = BuildConfig.APPLICATION_ID,
    appStoreUrl = "https://play.google.com/store/apps/details?id=com.mycompany.myapp",
    // ...
)
```

---

## Mode B — Prebid Server S2S

Prebid Mobile makes a single call to a Prebid Server instance, which fans out to all configured bidders server-side. Bidder params live in the Prebid Server stored request for each placement — the SDK does not send them inline. By default the auction resolves through `prebid.sellwild.com`; the CDN `S2S_CONFIG` key or a local `prebidServer` override points it elsewhere.

**Requirements:**
- A running Prebid Server instance (self-hosted or managed).
  - [AppNexus hosted](https://prebid.adnxs.com/pbs/v1/openrtb2/auction)
  - [Rubicon hosted](https://prebid-server.rubiconproject.com/openrtb2/auction)
  - [Self-hosted](https://docs.prebid.org/prebid-server/hosting/pbs-hosting.html)

**Local override (precedence: local → remote `S2S_CONFIG` → default):**

```swift
// iOS — SellwildConfig.swift
c.prebidServer = PrebidServerConfig(
    accountId: "YOUR_ACCOUNT_ID",
    endpoint:  "https://prebid-server.example.com/openrtb2/auction",
    bidders:   ["appnexus", "rubicon", "ix", "openx"],
    timeout:   1500
)
```

```kotlin
// Android — SellwildConfig.kt
prebidServer = PrebidServerConfig(
    accountId = "YOUR_ACCOUNT_ID",
    endpoint  = "https://prebid-server.example.com/openrtb2/auction",
    bidders   = listOf("appnexus", "rubicon", "ix", "openx"),
    timeout   = 1500,
),
```

```typescript
// React Native / Core TypeScript
prebidServer: {
  accountId: 'YOUR_ACCOUNT_ID',
  endpoint:  'https://prebid-server.example.com/openrtb2/auction',
  bidders:   ['appnexus', 'rubicon', 'ix', 'openx'],
  timeout:   1500,
}
```

---

## Mode C — Prebid Mobile SDK (native)

The Prebid Mobile SDK runs natively in-process. It supports IDFA (iOS, with ATT permission) and GAID (Android). This is the path for every placement — banners (`SellwildAdView` / `SellwildAdBanner` / RN `SellwildBanner`), the all-in-one feed (`SellwildFeedView` / `SellwildFeed`), and `SellwildNativeAdView`.

### Setup

Nothing to add. `SellwildSDK` ships the namespace-shaded `SellwildPrebid` fork and Google Mobile Ads as required dependencies (SPM, CocoaPods, and Maven all resolve them).

1. Call `SellwildSDK.configure(partnerCode, slug)` at launch. It fetches remote config and bootstraps Prebid Mobile + GMA (idempotent).
2. Drop in `SellwildAdView` (or `SellwildFeedView`) and call `load()`. The view runs the auction and renders the winner through GAM (`.both`), plain GAM (`.gamOnly`), or Prebid's own renderer (`.prebidOnly`).

To bootstrap without `configure()`, call `SellwildPrebidMobile.bootstrap(with: config)` (iOS) or `SellwildPrebidMobile.bootstrap(context, config)` (Android) before the first ad load.

---

## External User IDs (eids) — partner-supplied

Authenticated universal IDs (UID2, ID5, LiveRamp RampID, …) restore addressability and
materially lift CPMs — but they are minted from the user's **email / login / consent**,
which only your app holds. **The SDK cannot generate them.** You obtain the ID(s) from
your identity provider and hand them to the SDK, which emits them as OpenRTB
`user.ext.eids` on every native Prebid auction (Mode C).

> This is **required partner wiring** — Sellwild provides the rail; you supply the IDs.

### Wiring

Set the IDs **once per user session**, after the SDK is configured/bootstrapped and
before (or at) your first ad load. Prebid Mobile does **not** persist eids across app
restarts — re-set them each launch after you resolve the user's identity.

**iOS**
```swift
import SellwildSDK

SellwildPrebidMobile.setExternalUserIds([
    SellwildEid(source: "uidapi.com", uids: [
        SellwildEidUID(id: uid2Token, atype: 3)                    // person-based
    ]),
    SellwildEid(source: "id5-sync.com", uids: [
        SellwildEidUID(id: id5Id, atype: 1, ext: ["linkType": 2])
    ]),
])
```

**Android**
```kotlin
import com.sellwild.sdk.SellwildPrebidMobile
import com.sellwild.sdk.SellwildEid
import com.sellwild.sdk.SellwildEidUid

SellwildPrebidMobile.setExternalUserIds(listOf(
    SellwildEid("uidapi.com", listOf(
        SellwildEidUid(uid2Token, atype = 3)
    )),
    SellwildEid("id5-sync.com", listOf(
        SellwildEidUid(id5Id, atype = 1, ext = mapOf("linkType" to 2))
    )),
))
```

Pass an empty array/list to clear previously set IDs (e.g. on logout).

### `atype` (OpenRTB agent type)

| Value | Meaning |
|---|---|
| 1 | Cookie / web |
| 2 | In-app device ID (IFA/DPID) |
| 3 | Person-based (authenticated — most universal IDs) |

Use the value your ID provider specifies; for an authenticated login-based ID, `3` is typical.

### Server-side permission

Emitting eids is necessary but not always sufficient: which bidders receive which eids is
governed by **eid permissions** in the Prebid Server stored request. By default Prebid
Server forwards eids to all bidders; if a bidder requires an explicit grant, coordinate
with your Prebid Server owner. Confirm delivery by inspecting a debug auction's resolved
request for `user.ext.eids`.

### What the SDK sources vs. what you supply

- **You (partner) supply** authenticated IDs (UID2/ID5/RampID) — the SDK cannot mint them.
- **Device-graph IDs** that Sellwild resolves for you: **GrowthCode Signal Resolve** (below)
  is now wired — the SDK calls GrowthCode, persists the returned GCID, and merges its eids
  into the same auction. Your explicitly-set `setExternalUserIds` still win on conflict.

---

## GrowthCode Signal Resolve — SDK-resolved identity

The eids above are IDs **you** mint and hand in. GrowthCode Signal Resolve is the
counterpart the **SDK resolves for you**: when enabled, the SDK POSTs a "sync" to
GrowthCode, persists the returned **GCID**, and merges GrowthCode's returned eids into
every native Prebid auction — no partner wiring beyond a CMS toggle + a GrowthCode
Partner ID. It is **OFF by default** and controlled entirely from the CMS (no app release
to turn on/off). Wired identically on iOS, Android, and React Native; the pure logic also
lives in `@sellwild/sdk-core` (`growthcode.ts`) so a future web build shares it.

### How it works

1. On the first ad load of a launch (once, throttled), the SDK reads the config and — if
   enabled with a Partner ID — POSTs to `{endpoint}?pid={partnerId}&u={syncUrl}` with a
   form body carrying any stored `gcid`, the publisher host `h`, and (see MAID policy) the
   device advertising id.
2. GrowthCode returns `gc_id` (persisted on device) and `eb`, a serialized EID blob. The
   SDK parses `eb` into `SellwildEid`s and feeds them into the auction via the same
   `user.ext.eids` rail as partner-supplied eids.
3. **Merge rule:** GrowthCode's eids are merged with your `setExternalUserIds` eids;
   **on a source conflict your explicitly-set eids win** and fully suppress GrowthCode's
   entry for that source.
4. **Throttle:** the SDK calls GrowthCode only when it has **no stored GCID** or when
   **`GROWTHCODE_TTL_HOURS` (default 48)** have elapsed since the last sync. Inside the
   window it re-injects the **cached** eids (no billed call), so the auction keeps the
   signal between syncs.

### MAID policy (IDFA / GAID) — you own the permission surface, not us

GrowthCode match rates improve with the device advertising id, but the SDK will **never**
prompt for it or take on your ad-tracking regulatory surface:

- **iOS:** the SDK only *reads* the IDFA the system already grants. It does **not** call
  `requestTrackingAuthorization` — if the host app hasn't obtained ATT authorization, iOS
  returns the zeroed id and the SDK treats it as "no device id."
- **Android:** the GAID is read by **reflection**, with **no new Play Services dependency**.
  If the host app doesn't already bundle `play-services-ads-identifier`, the SDK simply has
  no GAID (it isn't your identity manager). Limit-ad-tracking is respected.
- **`GROWTHCODE_SEND_MAID`** (default **on**): when **off**, the SDK **skips the GrowthCode
  call entirely** for devices with no usable advertising id — GrowthCode bills per call, so
  this stops paying for signal-less requests. When on, the call still runs without a MAID.

See [privacy.md](docs-site/guide/privacy.md) for the data-flow and privacy-manifest note.

### Configuration

Everything is remote-first (CMS), with an optional local override that wins per field
(same precedence as S2S config: **local → remote `GROWTHCODE_*` → default**).

| Remote key (CMS) | Local field (`growthCode.*`) | Purpose |
|---|---|---|
| `GROWTHCODE_ENABLED` / `_BY_ZONE` | `enabled` | master on/off (global forces on; else per-zone) |
| `GROWTHCODE_PARTNER_ID` | `partnerId` | the `pid` — **required** for the sync to run |
| `GROWTHCODE_ENDPOINT` | `endpoint` | sync endpoint (default `https://ids.api.gcprivacy.id/v4/sync/api`) |
| `GROWTHCODE_SYNC_URL` | `syncUrl` | publisher domain sent as `u`/`h` (a native app has no page URL) |
| `GROWTHCODE_SEND_MAID` | `sendMaid` | send device id when available; off = skip signal-less calls |
| `GROWTHCODE_TTL_HOURS` | `ttlHours` | min hours between billed syncs (default 48) |

Typical setup is **CMS-only**: flip `GROWTHCODE_ENABLED`, set `GROWTHCODE_PARTNER_ID` and
`GROWTHCODE_SYNC_URL`. The local override is for code-pinned values:

**iOS**
```swift
let config = await SellwildSDK.configure(partnerCode: "weatherbug", slug: "weatherbug-main") {
    $0.growthCode = SellwildGrowthCodeConfig(partnerId: "YOUR_PID", syncUrl: "https://weatherbug.com")
}
```

**Android**
```kotlin
val config = SellwildSDK.configure(context, "weatherbug", "weatherbug-main").copy(
    growthCode = SellwildGrowthCodeConfig(partnerId = "YOUR_PID", syncUrl = "https://weatherbug.com"),
)
```

**React Native** — remote keys ride the `remote` passthrough automatically; the local
override rides the config prop:
```tsx
<SellwildBanner config={{ ...config, growthCode: { partnerId: 'YOUR_PID', syncUrl: 'https://weatherbug.com' } }} size="300x250" zoneId="43" />
```

### Prerequisites & notes

- **No native stored-imp change required** — GrowthCode eids ride the existing auction; you
  do **not** need a separate stored impression the way the native ad *format* does.
- A GrowthCode **Partner ID** is required; without `GROWTHCODE_PARTNER_ID` the sync no-ops.
- GCID + last-sync + the last EID blob are stored in `UserDefaults` /
  `SharedPreferences("sellwild_sdk")`, keyed per Partner ID (unencrypted — it is an ad id,
  not PHI).

---

## Geo (`device.geo`) — partner-supplied

Weather/utility apps usually know the user's location before the ad SDK would.
Passing it in lets DSPs value the impression on real geo instead of coarse IP,
and exposes `state` to non-ad consumers (e.g. per-state listing caches).

### Type

`SellwildGeo` — all fields optional; only what you set is sent. Maps to OpenRTB
`device.geo` (note `state` → `region`):

| field | OpenRTB | notes |
|---|---|---|
| `country` | `geo.country` | ISO-3166-1 alpha-3, e.g. `USA` |
| `state` | `geo.region` | also the key for per-state consumers |
| `city` | `geo.city` | |
| `zip` | `geo.zip` | |
| `metro` | `geo.metro` | DMA |
| `lat` / `lon` | `geo.lat` / `geo.lon` | |
| `type` | `geo.type` | 1 = GPS, 2 = IP, 3 = user |

### Wiring

Set at configure time (seeds both the auction and the shared store):

```swift
config.geo = SellwildGeo(country: "USA", state: "NY", zip: "10001")
```
```kotlin
config = config.copy(geo = SellwildGeo(country = "USA", state = "NY", zip = "10001"))
```

Or update at runtime — re-emits the combined ORTB config, preserving
`app.publisher.id`:

```swift
SellwildPrebidMobile.setGeo(SellwildGeo(state: "CA"))
```
```kotlin
SellwildPrebidMobile.setGeo(SellwildGeo(state = "CA"))
```

### Reading it outside the ad path

The current geo lives in a process-wide, thread-safe store — readable by the
listings feed or host-app code, not just the Prebid auction:

```swift
let state = SellwildGeoStore.current?.state
```
```kotlin
val state = SellwildGeoStore.current?.state
```

> **React Native:** the `pbsDebug` flag is bridged today. `geo` passthrough
> (nested marshalling) and a JS runtime `setGeo` are pending — RN's ad bridge is
> view-manager-only, so a callable `setGeo` needs a new native method module.

## Device type (`device.devicetype`) — automatic

Emitted on every native Prebid auction so DSPs and source-side analytics can
bucket demand by device class. No partner wiring — the SDK derives it from the
platform UI idiom and merges it into the same global ORTB `device` object that
carries `device.geo`.

| idiom (iOS `UIUserInterfaceIdiom`) | OpenRTB `device.devicetype` (IAB enum) |
|---|---|
| phone | `4` (PHONE) |
| pad | `5` (TABLET) |
| anything else (unknown / tv / carPlay / vision) | `1` (MOBILE/TABLET) fallback |

The iOS Prebid fork populates `device.os` / `make` / `model` / `ua` but not
`devicetype`; Android emits `devicetype` end-to-end via its Prebid fork. iOS
closes the gap by injecting the value through `setGlobalORTBConfig`, so
`ios` / `ipados` rows now carry `devicetype` alongside `android`.

## Debug flags — `debug` vs `pbsDebug`

Two independent, locally-configurable toggles (also settable remotely via the
CDN `DEBUG` / `PBS_DEBUG` keys):

| flag | effect |
|---|---|
| `debug` | Raises Prebid Mobile SDK **log verbosity** and enables the SDK's own render/auction diagnostics. |
| `pbsDebug` | Flips Prebid Mobile's `pbsDebug` → adds `ext.prebid.debug=1` + `returnallbidstatus` to the auction so the **response** carries the full server debug block (per-bidder status, `resolvedrequest`, cache calls). Heavier responses — leave OFF in production. |

`pbsDebug` surfaces on-device the same auction detail you'd otherwise only get
from a `debug=1` server curl. The two are orthogonal — verbose logs without heavy
responses, or vice-versa.

```swift
config.debug = true      // SDK logs
config.pbsDebug = true   // server-side auction debug block
```
```kotlin
config = config.copy(debug = true, pbsDebug = true)
```

## Outstream Video

The SDK supports **outstream (in-banner) video** in the standard banner slot (e.g. 300×250) — autoplay muted, plays when in view. It's **off by default** and toggled entirely from remote config, so you enable/disable it per zone from the CDN with **no app release**.

**Enable (remote config / CDN):**
```json
{ "VIDEO_ENABLED": true }
```
```json
{ "VIDEO_ENABLED_BY_ZONE": { "43": true } }
```
When on, the SDK requests a multiformat (banner + video) impression; when off, it's banner-only (unchanged). Precedence mirrors `AD_STACK`: global flag, then per-zone.

**Rendering depends on the ad stack (`AD_STACK`):**

| Stack | Renders via | Extra setup |
|-------|-------------|-------------|
| `prebidOnly` | Prebid's own renderer | none — Prebid plays the outstream video itself |
| `both` (default) | GAM | **GAM outstream line item / renderer required** |

On `both` zones, provision the GAM outstream creative **before** enabling video, or a winning video bid can win-but-not-render (lost impression). On `prebidOnly` zones, just flip the flag.

**SDK video defaults:** mp4; VAST 2.0–4.0; autoplay sound-off; OMID + MRAID (no VPAID); in-banner / standalone; 5–30s.

**Requirements:** an SDK version that ships outstream video; SSPs with active video seats.

---

## Muting auto-play creative audio (best-effort)

Some banner / MRAID creatives autoplay video or audio **with sound**, unprompted. The SDK ships a best-effort **audio guard** that mutes it entirely on the client — no server or CMS change:

- When a creative renders in a `SellwildAdView` slot, the SDK finds the ad's WebView(s) in its own view tree and injects a small mute shim (patches `HTMLMediaElement.play` to force-mute, mutes existing `<video>/<audio>`, and keeps muting new media via a `MutationObserver`), re-applied on a few short retries.
- **Muted video still autoplays** (viewability is preserved); only *sound* is targeted.

**Toggle (remote config / CDN):**
```json
{ "MOBILE_AD_MUTE_AUTOPLAY": false }
```
On by default; set `false` to disable.

> **Best-effort, by design.** It reaches media in the WebView's **main frame** only — a creative whose media is inside a cross-origin `<iframe>` is walled off by the same-origin policy, and creatives rendered in **GAM/AdX's own** container (not ours) are out of reach. For those, block auto-play-audio creatives in Google Ad Manager. Full ad-quality coverage (auto-redirects, malware, heavy ads) is the domain of dedicated vendors (Boltive, AppHarbr); this guard targets the common unsolicited-audio case.

---

## Native Ad Format

The SDK supports the **Prebid native ad format** in the standard ad slot. Unlike banner/outstream — which the fork auto-renders — native returns raw **assets** (title, body, icon, main image, CTA, sponsoredBy) that the SDK lays out into a default template (icon + title + sponsoredBy on top, main media in the middle, body + CTA at the bottom) and registers for impression / click tracking. It's **off by default** and toggled entirely from remote config, so you enable/disable it per zone from the CDN with **no app release**.

**Enable (remote config / CDN):**
```json
{ "NATIVE_ENABLED": true }
```
```json
{ "NATIVE_ENABLED_BY_ZONE": { "280": true } }
```
Precedence mirrors `AD_STACK` / `VIDEO_ENABLED`: global flag, then per-zone.

**Rendering depends on the ad stack (`AD_STACK`):**

| Stack | Behavior |
|-------|----------|
| `prebidOnly` | Native renders — the SDK fetches demand and lays out the assets itself, no GAM. |
| `both` / `gamOnly` | Native is **ignored**; the zone falls through to a banner. A GAM-rendered native creative needs GAM native line items + a `GADNativeAd` renderer (ad-ops) and is out of scope. |

So native only takes effect on `prebidOnly` zones. On a `both`/`gamOnly` zone the flag is a no-op until that zone is moved to `prebidOnly`.

**SDK native assets requested:** title (≤90 chars), icon image, **main image at ~1.91:1** (landscape, so returned media has a predictable height), sponsoredBy, body (≤140 chars), CTA text, impression event tracker. The server-side stored request must offer these assets.

**Height cap.** Native has no protocol max-height (the image asset only carries `w/h/wmin/hmin`, and total height is a function of your layout, not the bid), so the SDK enforces a **render-side cap** — remote-config, per-zone, same precedence as the enable toggle:
```json
{ "NATIVE_MAX_HEIGHT": 300 }
```
```json
{ "NATIVE_MAX_HEIGHT_BY_ZONE": { "280": 360 } }
```
Unset defaults to the placement slot height, so the view is always bounded. Under the cap the **main image absorbs the squeeze** while title / sponsoredBy / body / CTA keep their size — a tight cap never clips the CTA. The ~1.91:1 image request above makes the media predictable so the cap rarely has to clip. On React Native the slot **tracks the rendered height automatically** (see [Dynamic slot sizing](#dynamic-slot-sizing)), so a taller-than-slot cap renders taller with no extra wiring.

**Requirements:** an SDK version that ships the native format (1.5+); SSPs with active native seats; the placement resolved to `prebidOnly`.

---

## Multi-Size Banners

A placement can request more than one banner size in a single auction so demand falls back to a smaller creative when the primary doesn't fill — e.g. no 300×250 → take 320×50. It's one unified auction: bidders bid on whichever sizes they have, the best net bid wins, and that size renders. Sizes are remote-config, per-zone:

```json
{ "BANNER_SIZES": ["300x250", "320x50"] }
```
```json
{ "BANNER_SIZES_BY_ZONE": { "280": ["300x250", "320x50"] } }
```

The placement **primary** (the `AdSize` the host passes to the ad view) is always requested and always first; `BANNER_SIZES` entries are additional. Accepts `"WxH"` strings or `[w,h]` pairs; per-zone overrides global.

**Applies to all three stacks:**

| Stack | How sizes are applied |
|-------|-----------------------|
| `both` / `gamOnly` | GAM `validAdSizes` / `setAdSizes` — the solid path; GAM line items + AdX fill the fallback sizes. |
| `both` (Prebid bid) | Additional sizes attached to the Prebid `BannerAdUnit` so SSPs bid every size. |
| `prebidOnly` | Additional sizes attached to the rendering `BannerView`. |

> The GAM path is the well-supported one. The Prebid-bid and `prebidOnly` multi-size calls depend on the shaded fork's `addAdditionalSize` API and are **verify-on-build** (isolated in `SellwildAdSizes`), same caveat as the video/native fork surface.

**Slot sizing:** with multiple sizes the rendered height varies by which size wins. In `both`/`gamOnly` GAM resizes the slot; in `prebidOnly` the `BannerView` renders the winning size. On React Native the `<SellwildBanner>` resizes itself to match — see below.

---

## Dynamic Slot Sizing

Ads that don't render at a fixed banner size — a multi-size fallback creative, an outstream video, or the capped native template — would otherwise clip (too tall) or leave whitespace (too short) inside a fixed slot. To handle this the native `SellwildAdView` reports its **rendered size** on every render:

- **iOS** — `SellwildAdViewDelegate.sellwildAdView(_:didRenderWithSize:)`
- **Android** — `SellwildAdView.Listener.onAdResize(adView, width, height)`

Native hosts can resize their container from this callback. **React Native does it for you:** the bridge forwards it as an `onAdResize` event and `<SellwildBanner>` tracks the size in state, so the slot grows/shrinks to the actual creative with no app code.

**Baseline reservation (no clip).** The slot does **not** start at the primary size — it starts at the **bounding box of the requested size set** (`max(width) × max(height)` across the primary + `BANNER_SIZES` fallbacks). This matters because fallbacks can be *wider* than the primary — e.g. a `320×50` fallback in a `300×250` MREC request (320 > 300) — or taller. Reserving the bounding box means a fallback creative never clips, in any dimension, before or without the resize callback. The SDK computes this on all platforms (`SellwildAdSizes.boundingSize`); RN computes it in JS from the `BANNER_SIZES` it receives via `remote`. `didRenderWithSize` / `onAdResize` then reports the **actual** rendered size so the slot can tighten to fit.

Reported size by path: `both`/`gamOnly` → the winning GAM creative size (slot tightens); native → the capped template height; `prebidOnly` banner → the primary size (the rendering `BannerView` doesn't surface the winning multi-size creative to the callback — a known limitation, so a prebidOnly slot **stays at the reserved bounding box** rather than tightening, but it never clips). Feed ad rows are not yet self-sizing.

---

## Choosing a Configuration

There is no mode to choose on mobile. Every placement runs Mode C (native Prebid Mobile), and every Mode C auction resolves server-side through Prebid Server (Mode B).

| Scenario | What to change |
|----------|----------------|
| Default Sellwild demand | Nothing — `prebid.sellwild.com` via remote config |
| Your own Prebid Server | Set `S2S_CONFIG` in the CMS, or `prebidServer` locally |
| Skip GAM serving fees | Move the zone to `AD_STACK` `prebidOnly` |
| Regulatory compliance (TCF, CCPA) | Nothing — the native CMP bridges to Prebid Mobile |

---

## Reference: `PrebidServerConfig` Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | String | Yes | Your Prebid Server account ID |
| `endpoint` | String | Yes | Full auction endpoint URL |
| `bidders` | String[] | Yes | Bidder codes to route server-side |
| `timeout` | Int | No (default: 1500) | S2S auction timeout in ms |
| `syncEndpoint` | String? | No | `/cookie_sync` URL (derived from endpoint if omitted) |

---

## Further Reading

- [Prebid Server hosting guide](https://docs.prebid.org/prebid-server/hosting/pbs-hosting.html)
- [Prebid Mobile iOS SDK](https://docs.prebid.org/prebid-mobile/pbm-api/ios/pbm-api-ios.html)
- [Prebid Mobile Android SDK](https://docs.prebid.org/prebid-mobile/pbm-api/android/pbm-api-android.html)
- [ortb2.app specification (OpenRTB 2.6)](https://www.iab.com/wp-content/uploads/2022/04/OpenRTB-2-6_FINAL.pdf)
