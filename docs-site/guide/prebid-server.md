# Prebid Server Configuration Guide

This document covers the Sellwild managed Prebid Server instance at `prebid.sellwild.com`, including how server-side auctions work, configuration reference, SSP onboarding, GDPR enforcement, telemetry, and testing.

---

## Table of Contents

1. [Overview](#overview)
2. [How Server-Side Auctions Work](#how-server-side-auctions-work)
3. [Configuration Reference](#configuration-reference)
4. [SSP Onboarding](#ssp-onboarding)
5. [Supported Bidders](#supported-bidders)
6. [GDPR Enforcement](#gdpr-enforcement)
7. [Auction Telemetry](#auction-telemetry)
8. [Testing](#testing)
9. [House Ads and No-Fill Handling](#house-ads-and-no-fill-handling)
10. [Troubleshooting](#troubleshooting)

---

## Overview

`prebid.sellwild.com` is a managed Prebid Server instance that runs OpenRTB 2.6 server-side auctions on behalf of Sellwild SDK integrations. As of 1.3.0, the SDK runs banner auctions through the native Prebid Mobile SDK in-process; Prebid Mobile sends a single HTTP request to Prebid Server, which fans out to all configured SSPs server-side.

**Key benefits:**

- Native device signals (IDFV / AAID, ATT status, OS version) are passed to demand instead of being scrubbed by WebView restrictions.
- Reduces client-side JavaScript payload -- no individual bidder adapter scripts run on the device.
- Centralizes bidder timeout enforcement on the server.
- Enables server-side GDPR and consent enforcement via `regs.ext.gdpr`.
- Provides deterministic auction telemetry (response times, bid prices) via response extensions.

**Endpoint:**

```
https://prebid.sellwild.com/openrtb2/auction
```

---

## How Server-Side Auctions Work

The following diagram illustrates the OpenRTB request flow when the SDK is configured with `PrebidServerConfig`:

<AuctionFlowDiagram />

**Step-by-step:**

1. On first banner load, the SDK initializes the native Prebid Mobile SDK with the configured `accountId`, `endpoint`, and `timeout`.

2. Prebid Mobile constructs an OpenRTB 2.6 bid request and POSTs it to `prebid.sellwild.com/openrtb2/auction`. The request includes:
   - `imp[]` -- impression objects with ad unit sizes and floor prices.
   - `app{}` -- in-app traffic declaration with bundle ID and store URL.
   - `device{}` -- IDFV / AAID, OS, ATT status, and other native device signals.
   - `regs.ext.gdpr` and `user.ext.consent` -- GDPR signal and TCF v2 consent string read from `IABTCF_*` keys.

3. Prebid Server parses the request and fans out parallel OpenRTB bid requests to each configured SSP endpoint.

4. SSPs return bid responses (or no-bid) within the configured timeout window (default: 1500ms).

5. Prebid Server runs the auction logic: applies bid floors, enforces GDPR vendor consent, deduplicates bids, and selects the winning bid(s) per impression.

6. The consolidated response is returned to the client with `seatbid[]` containing winning bids and `ext.responsetimemillis` containing per-bidder latency data.

7. Prebid Mobile attaches targeting keywords (`hb_pb`, `hb_cache_id`, `hb_size`, …) to the GAM `AdManagerAdRequest`. GAM matches the line item and serves the cached creative into the native ad view.

---

## Configuration Reference

### PrebidServerConfig (SDK)

Configure Prebid Server in the SDK by setting the `prebidServer` field on `SellwildConfig`:

```dart
prebidServer: PrebidServerConfig(
  accountId: 'weatherbug',
  endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
  bidders: ['appnexus', 'pubmatic', 'ix', 'rubicon', 'openx'],
  timeout: 1500,
),
```

| Field          | Type           | Required | Default | Description                                                                 |
|----------------|----------------|----------|---------|-----------------------------------------------------------------------------|
| `accountId`    | `String`       | Yes      | --      | Your Prebid Server account ID. This is your Sellwild partner code.          |
| `endpoint`     | `String`       | Yes      | --      | Full URL: `https://prebid.sellwild.com/openrtb2/auction`                    |
| `bidders`      | `List<String>` | Yes      | --      | Bidder codes to include in the server-side auction. Must match server config.|
| `timeout`      | `int`          | No       | 1500    | Maximum time (ms) the server waits for SSP responses before closing auction.|
| `syncEndpoint` | `String?`      | No       | null    | Cookie sync endpoint. Derived from `endpoint` if omitted.                   |

### Server-Side Configuration

The following settings are managed on the Prebid Server instance at `prebid.sellwild.com`. They are documented here for transparency and to aid debugging. Changes to server-side configuration are made by the Sellwild ad operations team.

| Setting                          | Value / Description                                                    |
|----------------------------------|------------------------------------------------------------------------|
| `gdpr.default-value`             | `1` -- GDPR enforcement is on by default. See [GDPR Enforcement](#gdpr-enforcement). |
| `auction.timeout-ms`             | `1500` -- server-side default. Overridden by the client `timeout` field.|
| `auction.truncate-target-attr`   | `20` -- targeting key values are truncated to 20 characters.           |
| `adapters.<bidder>.enabled`      | Per-bidder enable/disable. See [Supported Bidders](#supported-bidders).|
| `cache.scheme` / `cache.host`    | Prebid Cache configuration for video/native creative caching.          |
| `metrics.type`                   | `prometheus` -- auction telemetry exported via Prometheus.             |

---

## SSP Onboarding

Adding a new SSP to your Prebid Server auction requires only your seat ID for that SSP. No server-side code changes or adapter development is needed -- Prebid Server ships with adapters for all major SSPs.

### Steps

1. **Obtain your seat ID** from the SSP. This is typically called a "publisher ID", "account ID", or "seat ID" depending on the SSP. Examples:
   - AppNexus: `placementId` (numeric, e.g., `12345678`)
   - Pubmatic: `publisherId` (string, e.g., `"156209"`)
   - Index Exchange: `siteId` (string, e.g., `"123456"`)
   - Rubicon: `accountId`, `siteId`, `zoneId` (all numeric)

2. **Provide the seat ID to the Sellwild ad operations team.** Include:
   - SSP name and bidder code (e.g., `appnexus`, `pubmatic`)
   - Your seat/account ID for that SSP
   - Any size restrictions or geo-targeting requirements

3. **Add the bidder code to your SDK configuration:**

   ```dart
   prebidServer: PrebidServerConfig(
     accountId: 'weatherbug',
     endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
     bidders: ['appnexus', 'pubmatic', 'ix', 'rubicon', 'openx', 'new_ssp'],
     timeout: 1500,
   ),
   ```

4. **Test the integration** using the curl commands in the [Testing](#testing) section. Verify the new bidder appears in `ext.responsetimemillis` in the response.

### What Sellwild Configures Server-Side

Once you provide your seat ID, the Sellwild team adds the bidder configuration to the Prebid Server account config:

```yaml
adapters:
  new_ssp:
    enabled: true
    endpoint: "https://ssp-endpoint.example.com/openrtb2"
    params:
      publisherId: "YOUR_SEAT_ID"
```

No SDK update or app release is required for server-side SSP changes.

---

## Supported Bidders

The following SSPs are available on `prebid.sellwild.com`. Use the **Bidder Code** value in your `PrebidServerConfig.bidders` list.

| SSP              | Bidder Code    | Required Params             | Notes                                    |
|------------------|----------------|-----------------------------|------------------------------------------|
| AppNexus (Xandr) | `appnexus`     | `placementId`               | Supports banner, video, native           |
| Pubmatic         | `pubmatic`     | `publisherId`, `adSlot`     | Supports banner, video                   |
| Index Exchange   | `ix`           | `siteId`                    | Banner and video                         |
| Rubicon (Magnite)| `rubicon`      | `accountId`, `siteId`, `zoneId` | Full-stack SSP                       |
| OpenX            | `openx`        | `unit`, `delDomain`         | Banner, video                            |
| TripleLift       | `triplelift`   | `inventoryCode`             | Native and display                       |
| Sharethrough     | `sharethrough`  | `pkey`                      | Native in-feed and display               |
| InMobi           | `inmobi`       | `plc`                       | Mobile-first; strong in-app demand       |
| Smaato           | `smaato`       | `publisherId`, `adspaceId`  | Mobile banner, interstitial, rewarded    |
| Yieldmo          | `yieldmo`      | `placementId`               | High-impact mobile formats               |
| Amazon TAM       | `amazontam`    | `slotId`                    | Requires Amazon Publisher Services setup |
| 33Across         | `33across`     | `siteId`, `productId`       | Viewable impression model                |
| Sovrn            | `sovrn`        | `tagid`                     | Banner, video                            |
| GumGum           | `gumgum`       | `zone`                      | In-image and in-screen formats           |
| Unruly           | `unruly`       | `siteId`                    | Outstream video                          |
| Rise (Emerse)    | `rise`         | `org`                       | Display and video                        |
| Criteo           | `criteo`       | `zoneId`                    | Retargeting demand                       |
| MediaNet         | `medianet`     | `cid`, `crid`               | Contextual demand                        |

To request a bidder not listed here, contact the Sellwild ad operations team with the bidder code from the [Prebid Server bidder list](https://docs.prebid.org/prebid-server/developers/add-new-bidder-go.html).

---

## GDPR Enforcement

### How It Works

`prebid.sellwild.com` is configured with `gdpr.default-value: 1`. This means:

- **When `regs.ext.gdpr` is absent from the bid request:** GDPR enforcement is applied by default. The server treats the request as if it originated from a GDPR-regulated region.
- **When `regs.ext.gdpr` is set to `1`:** GDPR enforcement is explicitly enabled. The server checks `user.ext.consent` for a valid TCF v2 consent string and suppresses bidders that do not have vendor consent.
- **When `regs.ext.gdpr` is set to `0`:** GDPR enforcement is explicitly disabled. All configured bidders receive the bid request.

### How the SDK Passes Consent

The native Prebid Mobile SDK reads the standard IAB TCF v2 storage keys (`IABTCF_TCString`, `IABTCF_gdprApplies`, …) that your CMP writes to platform storage (`SharedPreferences` on Android, `NSUserDefaults` on iOS). It then injects them into the OpenRTB request before sending it to Prebid Server:

```json
{
  "regs": {
    "ext": {
      "gdpr": 1
    }
  },
  "user": {
    "ext": {
      "consent": "BOJ/P2HOJ/P2HABABMAAAAAZ+A=="
    }
  }
}
```

- `regs.ext.gdpr` -- integer flag (0 or 1) indicating whether GDPR applies.
- `user.ext.consent` -- the IAB TCF v2 consent string read from `IABTCF_TCString`.

### Implications for Mobile Apps

If your CMP has not collected consent before the first auction runs, Prebid Mobile sends the request **without** a consent string. Because `gdpr.default-value` is `1`, Prebid Server then treats the request as subject to GDPR and bidders that require TCF consent will not receive it.

**Result:** In GDPR regions, auctions may return no bids unless consent is collected and persisted before the banner loads.

**Mitigation strategies:**

- **Use a TCF v2-compliant CMP** -- OneTrust, Didomi, Usercentrics, and similar SDKs all write the IABTCF_* keys natively. Prebid Mobile picks them up automatically.
- **Delay banner mount until consent is collected** -- gate `<SellwildBanner>` (or its native equivalent) behind your CMP completion callback so the first auction includes the consent string.
- **Non-GDPR regions** -- If your app serves only non-GDPR regions, set `gdprApplies = false` in your CMP or test with `"regs": { "ext": { "gdpr": 0 } }` using the curl commands below.

---

## Auction Telemetry

### Response Extensions

Every auction response from `prebid.sellwild.com` includes telemetry data in the `ext` object:

```json
{
  "seatbid": [...],
  "ext": {
    "responsetimemillis": {
      "appnexus": 120,
      "pubmatic": 85,
      "ix": 210,
      "rubicon": 0,
      "openx": 145
    },
    "tmaxrequest": 1500,
    "prebid": {
      "auctiontimestamp": 1714400000000
    }
  }
}
```

| Field                           | Description                                                        |
|---------------------------------|--------------------------------------------------------------------|
| `ext.responsetimemillis.<bidder>`| Time in ms each bidder took to respond. `0` = timed out or error. |
| `ext.tmaxrequest`               | The effective timeout used for this auction.                       |
| `ext.prebid.auctiontimestamp`   | Unix timestamp (ms) of when the auction was processed.             |

### Monitoring Bid Prices

Winning bid prices are returned in `seatbid[].bid[].price` (CPM in USD):

```json
{
  "seatbid": [
    {
      "seat": "appnexus",
      "bid": [
        {
          "id": "1",
          "impid": "imp-1",
          "price": 2.50,
          "adm": "<creative markup>",
          "w": 300,
          "h": 250
        }
      ]
    }
  ]
}
```

### Key Metrics to Track

| Metric                        | How to Derive                                                      | Healthy Range       |
|-------------------------------|--------------------------------------------------------------------|---------------------|
| Auction fill rate             | Requests with at least one `seatbid` / total requests              | 60--90% (varies)    |
| Average winning CPM           | Mean of `seatbid[].bid[].price` across filled auctions             | $0.50--$5.00        |
| Bidder timeout rate           | Count of `responsetimemillis` values = 0 / total bidder calls      | < 5%                |
| P95 server response time      | 95th percentile of total auction response latency                  | < 500ms             |
| Average bidder response time  | Mean of `responsetimemillis` per bidder                            | < 200ms             |

### Prometheus Metrics

`prebid.sellwild.com` exports Prometheus metrics. Contact the Sellwild team for access to the metrics endpoint or Grafana dashboards if you require real-time monitoring.

---

## Testing

### Verify the Endpoint

Confirm the Prebid Server endpoint is reachable:

```bash
curl -s -o /dev/null -w "%{http_code}" https://prebid.sellwild.com/openrtb2/auction
```

Expected output: `400` (the server rejects empty requests but confirms it is running).

### Send a Test Auction Request

The following curl command sends a minimal OpenRTB bid request to `prebid.sellwild.com` with a 300x250 banner impression:

```bash
curl -s -X POST https://prebid.sellwild.com/openrtb2/auction \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-request-001",
    "imp": [
      {
        "id": "imp-1",
        "banner": {
          "w": 300,
          "h": 250
        },
        "ext": {
          "prebid": {
            "bidder": {
              "appnexus": {
                "placementId": 13144370
              }
            }
          }
        }
      }
    ],
    "app": {
      "bundle": "com.aws.android",
      "storeurl": "https://play.google.com/store/apps/details?id=com.aws.android",
      "publisher": {
        "id": "weatherbug"
      }
    },
    "device": {
      "ua": "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36",
      "ip": "203.0.113.1",
      "os": "android",
      "osv": "13"
    },
    "tmax": 1500
  }' | python3 -m json.tool
```

### Expected Response Structure

A successful auction returns HTTP 200 with a JSON body:

```json
{
  "id": "test-request-001",
  "seatbid": [
    {
      "seat": "appnexus",
      "bid": [
        {
          "id": "bid-abc123",
          "impid": "imp-1",
          "price": 1.85,
          "adm": "<div><!-- creative markup --></div>",
          "w": 300,
          "h": 250,
          "crid": "98765"
        }
      ]
    }
  ],
  "cur": "USD",
  "ext": {
    "responsetimemillis": {
      "appnexus": 95
    },
    "tmaxrequest": 1500
  }
}
```

If no bidders return a bid, `seatbid` will be an empty array or absent from the response.

### Test Multiple Bidders

Include multiple bidders in a single request:

```bash
curl -s -X POST https://prebid.sellwild.com/openrtb2/auction \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-multi-bidder-001",
    "imp": [
      {
        "id": "imp-1",
        "banner": {
          "w": 300,
          "h": 250
        },
        "ext": {
          "prebid": {
            "bidder": {
              "appnexus": { "placementId": 13144370 },
              "pubmatic": { "publisherId": "156209", "adSlot": "slot1" },
              "ix": { "siteId": "123456" }
            }
          }
        }
      }
    ],
    "app": {
      "bundle": "com.aws.android",
      "storeurl": "https://play.google.com/store/apps/details?id=com.aws.android",
      "publisher": {
        "id": "weatherbug"
      }
    },
    "device": {
      "ua": "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36",
      "ip": "203.0.113.1",
      "os": "android",
      "osv": "13"
    },
    "tmax": 1500
  }' | python3 -m json.tool
```

Check `ext.responsetimemillis` in the response to verify each bidder was reached.

### Test with GDPR Consent

Verify that GDPR enforcement works correctly by sending a request with explicit consent signals:

```bash
curl -s -X POST https://prebid.sellwild.com/openrtb2/auction \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-gdpr-001",
    "imp": [
      {
        "id": "imp-1",
        "banner": { "w": 320, "h": 50 },
        "ext": {
          "prebid": {
            "bidder": {
              "appnexus": { "placementId": 13144370 }
            }
          }
        }
      }
    ],
    "app": {
      "bundle": "com.aws.android",
      "publisher": { "id": "weatherbug" }
    },
    "regs": {
      "ext": {
        "gdpr": 1
      }
    },
    "user": {
      "ext": {
        "consent": "BOJ/P2HOJ/P2HABABMAAAAAZ+A=="
      }
    },
    "tmax": 1500
  }' | python3 -m json.tool
```

To test GDPR blocking, send `"gdpr": 1` without a consent string. Bidders requiring consent should return no bids.

### Test with a Mobile Banner Size

Verify a 320x50 mobile banner auction:

```bash
curl -s -X POST https://prebid.sellwild.com/openrtb2/auction \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-mobile-banner-001",
    "imp": [
      {
        "id": "imp-1",
        "banner": {
          "w": 320,
          "h": 50,
          "format": [
            { "w": 320, "h": 50 }
          ]
        },
        "ext": {
          "prebid": {
            "bidder": {
              "appnexus": { "placementId": 13144370 }
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
      "ua": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
      "os": "ios",
      "osv": "17.0"
    },
    "tmax": 1500
  }' | python3 -m json.tool
```

---

## House Ads and No-Fill Handling

When no SSP returns a bid (a "no-fill"), the SDK falls back through the following chain:

1. **Prebid Server auction** -- if configured via `PrebidServerConfig`, Prebid Mobile sends the S2S request. If `seatbid` is empty, Prebid Mobile reports no demand.

2. **GAM passback** -- if `gamTag` is set in `SellwildConfig`, GPT requests the GAM ad unit. GAM can be configured with house ad line items that fill at a $0.00 CPM floor.

3. **Zone-based fallback** -- if `bannerZid` or `zoneId` is set, the SDK loads a creative from `bidstream.sellwild.com`. This can serve a house ad or a direct-sold campaign.

4. **Blank slot** -- if all of the above return empty, the ad slot renders as transparent. The `SellwildBanner` widget will display an empty `SizedBox` at the specified dimensions.

### Configuring House Ads

To ensure a house ad always fills when programmatic demand is unavailable:

- **In GAM:** Create a "House" line item with priority 16, $0.00 CPM, and assign a house creative. Target it to the same ad unit path used in `gamTag`.
- **Via Sellwild zones:** Contact the Sellwild ad operations team to configure a house creative on your zone ID. The zone ad server at `bidstream.sellwild.com` will return the house creative when no programmatic fill is available.

### Controlling Refresh on No-Fill

The SDK respects `maxFailedAuctions` in `SellwildConfig` (default: 3). After three consecutive no-fill auctions on an ad slot, the SDK stops refreshing that slot to conserve bandwidth and battery.

```dart
SellwildConfig(
  partnerCode: 'weatherbug',
  listingsUrl: '...',
  maxFailedAuctions: 5,          // Allow more retries before stopping
  adRefreshInterval: Duration(seconds: 45),  // Slow down refresh rate
)
```

---

## Troubleshooting

### GDPR Blocking -- No Bids in European Regions

**Symptom:** Auctions return empty `seatbid` for users in EU/EEA countries, but fill normally in the US.

**Cause:** `prebid.sellwild.com` has `gdpr.default-value: 1`. Without a TCF consent string in the request, bidders that require consent will not bid.

**Resolution:**
1. Verify your request includes `regs.ext.gdpr` and `user.ext.consent` by testing with curl (see [Testing](#testing)).
2. If using a native CMP, ensure consent is collected and the `IABTCF_*` keys are written before the first banner auction runs.
3. For testing, send `"regs": { "ext": { "gdpr": 0 } }` to confirm bids return when GDPR is not enforced. Do not ship this override to production for EU traffic.

### DNS Errors on Rubicon or Index Exchange with Test IDs

**Symptom:** `ext.responsetimemillis` shows `0` for `rubicon` or `ix`, and server logs show DNS resolution failures.

**Cause:** Rubicon and Index Exchange use account-specific endpoints derived from your seat IDs (e.g., `{accountId}-ssp.rubiconproject.com`). When using placeholder or test seat IDs, the derived hostname does not exist in DNS.

**Resolution:**
1. Replace test seat IDs with your production IDs from Rubicon/IX.
2. Verify the bidder endpoint resolves: `dig +short {accountId}-ssp.rubiconproject.com`
3. If you do not have a production account with these SSPs, remove them from the `bidders` list until onboarding is complete.

### No Fill -- All Bidders Time Out

**Symptom:** `ext.responsetimemillis` shows `0` for all bidders. `seatbid` is empty.

**Possible causes:**
- **Network connectivity:** The Prebid Server instance cannot reach SSP endpoints. This is a server-side issue -- contact the Sellwild team.
- **Invalid seat IDs:** Bidders reject requests with unrecognized account IDs. They may return HTTP 204 (no content) or an error before the timeout.
- **Timeout too low:** If `timeout` is set below 500ms, slow bidders will be cut off. Increase to 1500ms.
- **Request validation failure:** The OpenRTB request may be missing required fields. Check that `app.bundle` and `app.publisher.id` are set.

**Debugging steps:**
1. Test with a known-good bidder and placement ID (e.g., AppNexus test placement `13144370`).
2. Increase timeout to 3000ms temporarily.
3. Add `"test": 1` to the OpenRTB request root to enable test mode (bidders return synthetic bids).

### No Fill -- Bidders Respond but Do Not Bid

**Symptom:** `ext.responsetimemillis` shows non-zero values (bidders were reached), but `seatbid` is empty.

**Possible causes:**
- **Floor prices too high:** Your `floorMultiplier` in `SellwildConfig` or ad unit floors may be above the market clearing price.
- **Geo-targeting mismatch:** The `device.ip` or `device.geo` in the request maps to a region the SSP does not serve.
- **Ad size not supported:** Some SSPs do not support all IAB sizes. Verify the `banner.w` and `banner.h` values are standard sizes.
- **App bundle not recognized:** Some SSPs have allowlists. Confirm your `app.bundle` is registered with the SSP.

### SDK Reports "Prebid Server Unreachable"

**Symptom:** The `onError` callback fires with a network error when `PrebidServerConfig` is set.

**Steps:**
1. Verify the endpoint URL is correct: `https://prebid.sellwild.com/openrtb2/auction`
2. Test reachability from the device: open `https://prebid.sellwild.com` in the device browser.
3. Check for corporate firewalls or VPNs that may block the domain.
4. Verify the device has an active internet connection.

### High Bidder Latency

**Symptom:** `ext.responsetimemillis` shows values above 500ms for certain bidders, causing slow ad load times.

**Resolution:**
1. Review which bidders are slow. If a bidder consistently exceeds 300ms, consider removing it to improve user experience.
2. Reduce the `timeout` value to cap auction duration (e.g., 1000ms instead of 1500ms). Bidders that do not respond within the timeout are excluded.
3. Reduce the number of bidders. Each additional bidder adds marginal latency to the server-side fan-out.

### Prebid Mobile reports "Bidder timeout" or "No bids"

**Cause:** The OpenRTB request reached Prebid Server but no SSP returned a usable bid before `timeout` elapsed.

**Resolution:**
1. Inspect Prebid Mobile logs in Xcode console / `adb logcat` for the per-bidder response times.
2. Increase `timeout` modestly (e.g., 1500 → 1800 ms) if upstream latency is high.
3. Verify the bidder list in `PrebidServerConfig.bidders` matches what is enabled on the server side for your `accountId`.
