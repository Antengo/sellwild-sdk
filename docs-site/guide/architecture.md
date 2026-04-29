# Architecture

This page describes how the Sellwild SDK works internally -- from the moment your app requests an ad through final creative rendering and event tracking.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Request Flow](#request-flow)
3. [OpenRTB Request Lifecycle](#openrtb-request-lifecycle)
4. [Bid Matching](#bid-matching)
5. [Creative Rendering](#creative-rendering)
6. [House Ad Fallback Chain](#house-ad-fallback-chain)
7. [Event Tracking Pipeline](#event-tracking-pipeline)

---

## System Overview

The Sellwild SDK uses a server-to-server (S2S) architecture for programmatic ad auctions. No client-side bidder adapters run on the device. A single HTTP request to the managed Prebid Server instance replaces the traditional waterfall of sequential SDK calls.

```
+-----------------------------------------------------------------+
|  Your Mobile App                                                |
|                                                                 |
|  +-----------------------------------------------------------+ |
|  |  Sellwild SDK (native layer)                               | |
|  |                                                            | |
|  |  +------------------+  +------------------+  +-----------+ | |
|  |  | SellwildAdView   |  | SellwildWidget   |  | API Client| | |
|  |  | (banner, MREC,   |  | (listing carousel|  | (listings | | |
|  |  |  video, interst.)|  |  + embedded ads) |  |  fetch)   | | |
|  |  +--------+---------+  +--------+---------+  +-----+-----+ | |
|  |           |                      |                  |       | |
|  |  +--------v----------------------v------------------v-----+ | |
|  |  |  Managed WebView (WKWebView / Android WebView)         | | |
|  |  |                                                        | | |
|  |  |  Prebid.js (S2S mode)                                  | | |
|  |  |    - ortb2.app signals injected                        | | |
|  |  |    - iframe syncs disabled                             | | |
|  |  |    - s2sConfig pointing to prebid.sellwild.com         | | |
|  |  +------------------------+-------------------------------+ | |
|  +---------------------------|-------------------------------+  |
+-----------------------------|-----------------------------------+
                              |
                    HTTPS POST /openrtb2/auction
                              |
                              v
+-----------------------------+-----------------------------------+
|  prebid.sellwild.com  (Prebid Server)                           |
|                                                                 |
|  +-----------------------------------------------------------+ |
|  |  OpenRTB 2.6 Auction Engine                                | |
|  |                                                            | |
|  |  - Parse imp[], app{}, device{}, regs{}, user{}            | |
|  |  - Enforce GDPR / TCF v2 vendor consent                   | |
|  |  - Apply bid floors                                        | |
|  |  - Fan out parallel bid requests to configured SSPs        | |
|  |  - Collect responses within timeout window                 | |
|  |  - Run auction: select winning bid per impression          | |
|  |  - Return seatbid[] with creative markup (adm)             | |
|  +---+----------+----------+----------+----------+-----------+ |
|      |          |          |          |          |              |
+------|----------|----------|----------|----------|-------------+
       v          v          v          v          v
  +---------+ +---------+ +------+ +-------+ +--------+
  | AppNexus| | PubMatic| | IX   | |Rubicon| | OpenX  |  ... 400+
  +---------+ +---------+ +------+ +-------+ +--------+
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Server-side auctions | WebViews block third-party cookies; client-side adapters cannot sync user IDs reliably |
| `ortb2.app` injection | Ensures DSPs classify traffic as in-app (not web), enabling app-ads.txt enforcement |
| Iframe sync disabled | WKWebView and Android WebView reject third-party cookie writes; suppresses wasted HTTP requests |
| Single WebView per ad view | Isolates ad sessions; prevents cross-contamination between ad units |

---

## Request Flow

The following diagram traces a single ad request from the app through to creative rendering.

```
  App                       SDK WebView               Prebid Server             SSPs
   |                            |                          |                      |
   |  1. load()                 |                          |                      |
   +--------------------------->|                          |                      |
   |                            |                          |                      |
   |  2. Build HTML with        |                          |                      |
   |     s2sConfig, ortb2.app,  |                          |                      |
   |     userSync filters       |                          |                      |
   |                            |                          |                      |
   |  3. Load Prebid.js         |                          |                      |
   |     (from CDN or custom    |                          |                      |
   |      prebidSrc URL)        |                          |                      |
   |                            |                          |                      |
   |                            |  4. POST /openrtb2/auction                     |
   |                            |     {imp[], app{}, device{}, regs{}, tmax}      |
   |                            +------------------------->|                      |
   |                            |                          |                      |
   |                            |                          |  5. Parallel bid     |
   |                            |                          |     requests to each |
   |                            |                          |     configured SSP   |
   |                            |                          +--------------------->|
   |                            |                          |                      |
   |                            |                          |  6. Bids returned    |
   |                            |                          |     (or no-bid)      |
   |                            |                          |<---------------------+
   |                            |                          |                      |
   |                            |                          |  7. Run auction:     |
   |                            |                          |     apply floors,    |
   |                            |                          |     enforce consent, |
   |                            |                          |     pick winner(s)   |
   |                            |                          |                      |
   |                            |  8. BidResponse          |                      |
   |                            |     {seatbid[], ext{}}   |                      |
   |                            |<-------------------------+                      |
   |                            |                          |                      |
   |  9. Render winning         |                          |                      |
   |     creative (adm) in      |                          |                      |
   |     WebView ad slot        |                          |                      |
   |                            |                          |                      |
   |  10. JS bridge fires       |                          |                      |
   |      AD_LOADED callback    |                          |                      |
   |<---------------------------+                          |                      |
   |                            |                          |                      |
   |  11. Impression pixel      |                          |                      |
   |      fires (viewability)   |                          |                      |
   |                            |                          |                      |
   |  12. JS bridge fires       |                          |                      |
   |      AD_IMPRESSION callback|                          |                      |
   |<---------------------------+                          |                      |
```

### Timing

| Phase | Typical Duration |
|-------|-----------------|
| Steps 1-3: WebView + Prebid.js initialization | 100-300 ms |
| Step 4: HTTP request to Prebid Server | 20-50 ms (network) |
| Steps 5-6: Server-side SSP fan-out | 50-200 ms (bounded by `timeout`) |
| Step 7: Auction logic | < 5 ms |
| Steps 8-9: Response + creative render | 50-150 ms |
| **Total** | **< 500 ms typical** |

---

## OpenRTB Request Lifecycle

### Outbound Request (SDK to Prebid Server)

The SDK constructs an OpenRTB 2.6 bid request with the following structure:

```json
{
  "id": "auction-1714400000000",
  "imp": [
    {
      "id": "imp-1",
      "banner": {
        "format": [{ "w": 300, "h": 250 }]
      },
      "ext": {
        "prebid": {
          "bidder": {
            "appnexus": { "placementId": 13144370 },
            "ix": { "siteId": "345678" }
          }
        }
      }
    }
  ],
  "app": {
    "bundle": "com.aws.android",
    "storeurl": "https://play.google.com/store/apps/details?id=com.aws.android",
    "publisher": { "id": "weatherbug" }
  },
  "device": {
    "ua": "Mozilla/5.0 (Linux; Android 14; Pixel 8)",
    "os": "android",
    "osv": "14"
  },
  "regs": {
    "ext": { "gdpr": 0 }
  },
  "tmax": 1500
}
```

### Key Fields

| Field | Purpose |
|-------|---------|
| `imp[]` | One entry per ad slot. Contains size, floor price, and per-bidder params. |
| `app.bundle` | Identifies the app for app-ads.txt verification and DSP targeting. |
| `app.publisher.id` | Maps to your Sellwild partner code (e.g., `"weatherbug"`). |
| `device` | User agent, OS, and optionally IP/geo for geo-targeted demand. |
| `regs.ext.gdpr` | GDPR applicability flag. `1` = enforced, `0` = not applicable. |
| `user.ext.consent` | TCF v2 consent string (when GDPR applies). |
| `tmax` | Maximum auction duration in milliseconds. |

### Inbound Response (Prebid Server to SDK)

```json
{
  "id": "auction-1714400000000",
  "seatbid": [
    {
      "seat": "appnexus",
      "bid": [
        {
          "id": "bid-abc123",
          "impid": "imp-1",
          "price": 2.50,
          "adm": "<div><!-- creative HTML markup --></div>",
          "w": 300,
          "h": 250,
          "adomain": ["advertiser.com"],
          "crid": "98765"
        }
      ]
    }
  ],
  "cur": "USD",
  "ext": {
    "responsetimemillis": {
      "appnexus": 95,
      "ix": 120
    },
    "tmaxrequest": 1500
  }
}
```

### Response Extensions

| Field | Description |
|-------|-------------|
| `seatbid[].bid[].price` | Winning CPM in USD. |
| `seatbid[].bid[].adm` | The creative markup to render (HTML for display, VAST XML for video). |
| `ext.responsetimemillis` | Per-bidder response latency. `0` indicates timeout or error. |
| `ext.tmaxrequest` | The effective timeout applied to this auction. |

---

## Bid Matching

Prebid Server matches bids to impression slots using the `impid` field.

```
Request                              Response
+---------------------------+        +---------------------------+
| imp[0]                    |        | seatbid[0].bid[0]         |
|   id: "imp-1"             | <----> |   impid: "imp-1"          |
|   banner: 300x250         |        |   price: 2.50             |
|   bidders: appnexus, ix   |        |   seat: "appnexus"        |
+---------------------------+        +---------------------------+
| imp[1]                    |        | seatbid[1].bid[0]         |
|   id: "imp-2"             | <----> |   impid: "imp-2"          |
|   banner: 320x50          |        |   price: 0.80             |
|   bidders: appnexus, openx|        |   seat: "openx"           |
+---------------------------+        +---------------------------+
```

### Auction Rules

1. **Per-impression auction.** Each `imp` entry runs an independent auction. Multiple impressions in a single request do not compete with each other.
2. **Highest CPM wins.** Within each impression, the bid with the highest `price` wins. Ties are broken by response time (first responder wins).
3. **Floor enforcement.** Bids below the configured floor price are discarded before auction ranking.
4. **GDPR filtering.** Bidders without valid TCF vendor consent are excluded before the fan-out. They never receive the bid request.
5. **Size matching.** The winning bid's `w` and `h` must match one of the `format` entries in the corresponding `imp.banner`. Mismatched sizes are rejected.

---

## Creative Rendering

After the auction, the SDK renders the winning creative based on its type. The creative type is indicated by `seatbid[].bid[].ext.prebid.type`.

### Display (HTML Banner)

The most common format. The `adm` field contains an HTML snippet.

```
Winning bid
  adm: "<div><a href='https://...'><img src='https://...'/></a></div>"
    |
    v
WebView renders HTML directly in the ad slot
    |
    v
Impression pixel fires when creative is viewable (MRC standard: 50% of
pixels visible for 1 continuous second)
```

The SDK sizes the WebView to match the ad dimensions (`w` x `h` from the bid). CSS within the WebView prevents scrolling and overflow.

### Video (VAST)

When the winning bid is a video creative, `adm` contains VAST XML.

```
Winning bid
  adm: "<VAST version='3.0'>...</VAST>"
    |
    v
Prebid.js parses VAST XML
    |
    v
Video player renders in the ad slot WebView
    |
    +-- Inline media playback enabled (allowsInlineMediaPlayback = true)
    +-- No fullscreen takeover on iPhone
    +-- Autoplay with muted audio (per platform policy)
    |
    v
VAST tracking events fire at quartile milestones:
  - start, firstQuartile, midpoint, thirdQuartile, complete
```

### Companion Images

Some video creatives include companion banners defined in the VAST `<CompanionAds>` element. When present:

1. The primary video renders in the main ad slot.
2. Companion images render in adjacent slots if available.
3. If no companion slot is configured, companion creatives are ignored.

### Native Ads

Native ad responses return structured JSON (title, description, image URL, CTA) rather than pre-rendered HTML. The SDK maps these fields to native UI components when using `SellwildListingCard` or custom listing layouts.

---

## House Ad Fallback Chain

When no SSP returns a winning bid, the SDK walks through a fallback chain to ensure the ad slot is never left empty (when possible).

```
+---------------------------+
| 1. Prebid Server Auction  |
|    (S2S via PBS)           |
+------------+--------------+
             |
        seatbid empty?
             |
        Yes  |
             v
+---------------------------+
| 2. GAM Passback           |
|    (if gamTag is set)      |
|                           |
|    GPT requests the GAM   |
|    ad unit. GAM can serve  |
|    house line items at     |
|    $0.00 CPM floor.        |
+------------+--------------+
             |
        No fill from GAM?
             |
        Yes  |
             v
+---------------------------+
| 3. Zone-Based Fallback    |
|    (if bannerZid or        |
|     zoneId is set)         |
|                           |
|    Loads a creative from   |
|    bidstream.sellwild.com. |
|    Can serve house ads or  |
|    direct-sold campaigns.  |
+------------+--------------+
             |
        No creative?
             |
        Yes  |
             v
+---------------------------+
| 4. Blank Slot             |
|                           |
|    The ad slot renders as  |
|    transparent. The view   |
|    maintains its declared  |
|    dimensions but shows    |
|    no content.             |
+---------------------------+
```

### Controlling No-Fill Behavior

| Config Field | Default | Effect |
|-------------|---------|--------|
| `gamTag` | `null` | When set, enables GAM passback as fallback step 2. |
| `bannerZid` / `zoneId` | `null` | When set, enables zone-based fallback as step 3. |
| `maxFailedAuctions` | `3` | After N consecutive no-fills, the SDK stops refreshing that slot. |
| `adRefreshInterval` | `30s` | Time between refresh attempts. Longer intervals reduce no-fill impact. |

---

## Event Tracking Pipeline

The SDK tracks ad lifecycle events and reports them to the Sellwild analytics backend.

```
+------------------+     +-------------------+     +-------------------+
| WebView          |     | Native SDK Layer  |     | Sellwild Backend  |
|                  |     |                   |     |                   |
| Ad creative      |     |                   |     |                   |
| renders          |     |                   |     |                   |
|   |              |     |                   |     |                   |
|   +-- AD_LOADED -+---->| onAdLoaded()      |     |                   |
|   |              |     |   |               |     |                   |
|   |              |     |   +-- Queue event  |     |                   |
|   |              |     |                   |     |                   |
| Viewability met  |     |                   |     |                   |
| (MRC standard)   |     |                   |     |                   |
|   |              |     |                   |     |                   |
|   +-- IMPRESSION-+---->| onAdImpression()  |     |                   |
|   |              |     |   |               |     |                   |
|   |              |     |   +-- Queue event  |     |                   |
|   |              |     |   +-- Fire imp     |     |                   |
|   |              |     |       pixel        |     |                   |
|   |              |     |                   |     |                   |
| User taps ad     |     |                   |     |                   |
|   |              |     |                   |     |                   |
|   +-- AD_CLICK --+---->| onAdClicked()     |     |                   |
|   |              |     |   |               |     |                   |
|   |              |     |   +-- Queue event  |     |                   |
|   |              |     |   +-- Open URL in  |     |                   |
|   |              |     |       system       |     |                   |
|   |              |     |       browser      |     |                   |
|   |              |     |                   |     |                   |
|   |              |     | EventQueue         |     |                   |
|   |              |     |   |               |     |                   |
|   |              |     |   +-- Batch flush -+---->| /events/queue     |
|   |              |     |       (timer or    |     |   (POST, batched) |
|   |              |     |        max-batch)  |     |                   |
+------------------+     +-------------------+     +-------------------+
```

### Event Types

| Event | Trigger | Data Included |
|-------|---------|---------------|
| `AD_LOADED` | Creative markup rendered in WebView | Zone ID, ad size, bidder |
| `IMPRESSION` | MRC viewability threshold met | Zone ID, CPM, bidder, creative ID |
| `AD_CLICK` | User tap on the creative | Zone ID, destination URL |
| `AD_ERROR` | Auction failure or render error | Error message, zone ID |
| `LISTING_CLICK` | User tap on a marketplace listing | Listing URL |
| `WIDGET_LOADED` | Listing widget initialization complete | Partner code |

### Batching and Delivery

The `EventQueue` (implemented per platform) batches events and flushes them to the Sellwild analytics endpoint:

- **Flush interval:** Events are sent every 5 seconds if any are queued.
- **Max batch size:** If the queue exceeds the batch limit, it flushes immediately.
- **Retry on failure:** Failed flushes re-queue events for the next cycle. Events are not dropped.
- **Persistent session ID:** A unique session identifier is stored in `UserDefaults` (iOS) or `SharedPreferences` (Android) and included with every event batch.

### Third-Party Tracking

In addition to SDK-level events, each winning creative fires its own tracking pixels:

- **SSP impression pixels:** Embedded in the creative `adm` markup. Fire when the creative renders.
- **VAST tracking events:** For video creatives, milestone events (start, quartiles, complete) fire per the VAST specification.
- **Viewability vendors:** If the creative includes Moat, IAS, or DoubleVerify scripts, they execute within the WebView sandbox.

These third-party pixels operate independently of the SDK event pipeline. The SDK does not intercept or modify them.
