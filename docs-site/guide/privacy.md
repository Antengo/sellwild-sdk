# Privacy & Consent

This page covers privacy regulation compliance for the Sellwild SDK, including GDPR, CCPA, GPP, App Tracking Transparency, and app-ads.txt.

---

## Table of Contents

1. [Overview](#overview)
2. [GDPR / TCF v2](#gdpr--tcf-v2)
3. [Prebid Server GDPR Enforcement](#prebid-server-gdpr-enforcement)
4. [CCPA / US Privacy](#ccpa--us-privacy)
5. [GPP Framework](#gpp-framework)
6. [iOS App Tracking Transparency](#ios-app-tracking-transparency)
7. [Android GAID](#android-gaid)
8. [app-ads.txt](#app-adstxt)
9. [Data Flow Diagram](#data-flow-diagram)

---

## Overview

The Sellwild SDK does not independently collect, store, or process personal data. All user data handling occurs through the Prebid Server auction flow, where consent enforcement is applied server-side.

| Privacy Framework | Responsibility | Where Enforced |
|-------------------|---------------|----------------|
| GDPR / TCF v2 | Host app collects consent via CMP | Prebid Server (`regs.ext.gdpr`) |
| CCPA / US Privacy | Host app determines opt-out status | Prebid Server (`regs.ext.us_privacy`) |
| GPP | Host app passes GPP string | Prebid Server (`regs.gpp`) |
| ATT (iOS IDFA) | Host app presents ATT prompt | OS-level; IDFA passed via `ortb2.user.eids` |
| GAID (Android) | Host app reads advertising ID | OS-level; not read by the SDK |

---

## GDPR / TCF v2

### How `gdprApplies` and `tcString` Work

The IAB Transparency and Consent Framework (TCF) v2 defines two key signals:

| Signal | OpenRTB Field | Type | Description |
|--------|--------------|------|-------------|
| GDPR applicability | `regs.ext.gdpr` | `Int` (0 or 1) | Whether GDPR applies to this user/request. |
| TC consent string | `user.ext.consent` | `String` | Base64-encoded TCF v2 consent string from your CMP. |

### Passing Consent from Your CMP

If your app uses a native Consent Management Platform (OneTrust, Didomi, Usercentrics, etc.), it stores consent in platform-standard locations:

| Platform | Storage | Key |
|----------|---------|-----|
| iOS | `UserDefaults` | `IABTCF_gdprApplies` (`Int`), `IABTCF_TCString` (`String`) |
| Android | `SharedPreferences` | `IABTCF_gdprApplies` (`Int`), `IABTCF_TCString` (`String`) |

**iOS example:**

```swift
let gdprApplies = UserDefaults.standard.integer(forKey: "IABTCF_gdprApplies")
let tcString = UserDefaults.standard.string(forKey: "IABTCF_TCString")

if gdprApplies == 1 {
    print("[Privacy] GDPR applies. TC string: \(tcString ?? "none")")
}
```

**Android example:**

```kotlin
val prefs = PreferenceManager.getDefaultSharedPreferences(context)
val gdprApplies = prefs.getInt("IABTCF_gdprApplies", 0) == 1
val tcString = prefs.getString("IABTCF_TCString", "") ?: ""
```

**React Native / Flutter:**

Pass the consent values directly through `SellwildConfig`:

```ts
const config = buildConfig({
  partnerCode: 'weatherbug',
  listingsUrl: 'https://api.sellwild.com/listings/weatherbug',
  gdprApplies: true,
  tcString: 'CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA',
  tcfVersion: 2,
  prebidServer: {
    accountId: 'weatherbug',
    endpoint: 'https://prebid.sellwild.com/openrtb2/auction',
    bidders: ['appnexus', 'rubicon', 'ix', 'openx'],
    timeout: 1500,
  },
});
```

### How the SDK Passes `regs.ext.gdpr` in ortb2

When `gdprApplies` and `tcString` are configured, the SDK injects the following into the Prebid.js pre-configuration script within the WebView:

```js
pbjs.setConfig({
    ortb2: {
        regs: {
            ext: { gdpr: 1 }
        },
        user: {
            ext: {
                consent: 'CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA'
            }
        }
    }
});
```

Prebid.js forwards these fields in the OpenRTB request body to Prebid Server. The server then includes them in each outbound bid request to SSPs.

### Native CMP Bridging

Prebid.js running in a WebView looks for `window.__tcfapi` to read consent. In a native app WebView, no CMP is running inside the WebView context, so `__tcfapi` does not exist.

**Mitigation strategies:**

1. **Prebid Server S2S mode (recommended).** When using `PrebidServerConfig`, consent is passed server-side via the OpenRTB `regs` and `user` fields. The WebView CMP API is not needed.
2. **Manual injection.** Read the TC string from native storage and inject it into the WebView before Prebid.js loads. This requires access to the WebView controller, which is not currently exposed by the SDK.
3. **In-widget CMP.** The web widget may implement its own CMP flow. Set `tcfVersion: 2` to enable this path.

### Best Practices

- Initialize your CMP before loading any ad views. The SDK reads consent at ad request time.
- If `gdprApplies` is `true` (or `1`) and no valid `tcString` is present, Prebid Server suppresses all bidders that require TCF consent.
- Do not cache or modify the TC string manually. Let your CMP manage its lifecycle.
- Test consent strings with the [IAB TCF Consent String Decoder](https://iabtcf.com/#/decode).

---

## Prebid Server GDPR Enforcement

The managed Prebid Server at `prebid.sellwild.com` is configured with:

```yaml
gdpr:
  default-value: 1
```

This means GDPR enforcement is **on by default**. The behavior depends on what the bid request contains:

| `regs.ext.gdpr` | `user.ext.consent` | Server Behavior |
|-----------------|---------------------|-----------------|
| Absent | Absent | GDPR enforced (default-value: 1). Bidders requiring consent are suppressed. |
| `1` | Valid TC string | GDPR enforced. Server checks vendor consent per bidder. Bidders with consent receive requests; others are excluded. |
| `1` | Absent or invalid | GDPR enforced. All consent-requiring bidders are suppressed. Auction likely returns no bids in EU. |
| `0` | Any | GDPR not enforced. All configured bidders receive the bid request. |

### Implications

- **US-only apps:** Explicitly set `gdprApplies: false` (or `regs.ext.gdpr: 0`) to avoid unintentional GDPR enforcement.
- **Global apps:** Use geo-detection in your CMP to set `gdprApplies` per user. Pass the result to the SDK config.
- **Testing:** Send test auction requests with `"regs": { "ext": { "gdpr": 0 } }` to confirm bids return when GDPR is disabled. Do not ship this override for EU traffic.

---

## CCPA / US Privacy

The California Consumer Privacy Act (CCPA) is supported through the IAB US Privacy string.

### Configuration

The US Privacy string follows the format `1YNN` where:
- Position 1: Version (`1`)
- Position 2: Sale opt-out notice (`Y` = provided, `N` = not provided, `-` = not applicable)
- Position 3: Sale opt-out (`Y` = opted out, `N` = not opted out, `-` = not applicable)
- Position 4: LSPA coverage (`Y` = yes, `N` = no, `-` = not applicable)

### How It Propagates

When using Prebid Server S2S mode, include the US Privacy string in the OpenRTB request:

```json
{
  "regs": {
    "ext": {
      "us_privacy": "1YNY"
    }
  }
}
```

Prebid Server forwards this field to all SSPs. SSPs that respect CCPA will suppress personalized bidding for opted-out users.

### GPP Supersedes US Privacy

The IAB Global Privacy Platform (GPP) is the successor to the standalone US Privacy string. When `gppEnabled: true`, the SDK uses GPP signaling instead. See [GPP Framework](#gpp-framework).

---

## GPP Framework

The IAB Global Privacy Platform provides a unified consent signaling mechanism that covers GDPR, CCPA, and other regional privacy regulations in a single framework.

### Enabling GPP

```swift
// iOS
config.gppEnabled = true
```

```kotlin
// Android
SellwildConfig(gppEnabled = true, ...)
```

```ts
// React Native
buildConfig({ gppEnabled: true, ... })
```

```dart
// Flutter
SellwildConfig(gppEnabled: true, ...)
```

### How It Works

When GPP is enabled:

1. The SDK sets the `consentManagement` configuration in Prebid.js to use the GPP module.
2. Prebid.js reads the GPP string from the CMP (via `window.__gpp` API or from the host app config).
3. The GPP string and applicable section IDs are included in the OpenRTB request as `regs.gpp` and `regs.gpp_sid`.
4. Prebid Server enforces consent based on the applicable GPP sections.

### GPP Sections

| Section ID | Regulation | Region |
|-----------|------------|--------|
| 2 | TCF v2 (GDPR) | EU/EEA |
| 6 | USP v1 (CCPA) | California |
| 7-12 | US state-level laws | Various US states |

---

## iOS App Tracking Transparency

On iOS 14.5+, the App Tracking Transparency (ATT) framework requires user permission before accessing the IDFA (Identifier for Advertisers). The IDFA improves ad targeting, frequency capping, and fill rates when passed through Prebid Server.

### Requesting ATT Authorization

```swift
import AppTrackingTransparency
import AdSupport

func requestTrackingAuthorization() {
    guard #available(iOS 14.5, *) else { return }

    ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async {
            switch status {
            case .authorized:
                let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                print("[Privacy] IDFA authorized: \(idfa)")
                // Pass IDFA to Prebid Server via ortb2.user.eids

            case .denied, .restricted:
                print("[Privacy] Tracking denied. Ads serve without IDFA.")

            case .notDetermined:
                print("[Privacy] Tracking not yet determined.")

            @unknown default:
                break
            }
        }
    }
}
```

### Info.plist Requirement

Add the usage description string to `Info.plist`:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier is used to deliver personalized ads and measure ad performance.</string>
```

### Timing Recommendations

- Present the ATT prompt after your app has loaded its initial UI. Prompting on first launch with no context results in lower opt-in rates.
- A common pattern: request authorization in `viewDidAppear` of your first content screen, or after a brief onboarding flow.
- The ATT prompt can only be presented once per install. Subsequent calls to `requestTrackingAuthorization` return the cached status without showing a dialog.
- Always check `ATTrackingManager.trackingAuthorizationStatus` before presenting ad UI that depends on the IDFA.

### IDFA and Prebid Server

The IDFA is not automatically read or passed by the SDK. To include it in bid requests, the host app must:

1. Request ATT authorization.
2. Read the IDFA from `ASIdentifierManager`.
3. Pass it to Prebid Server via the `ortb2.user.eids` field (planned SDK feature) or through a custom bid request when using the direct auction API.

```js
// How IDFA appears in the OpenRTB request (via ortb2.user.eids)
pbjs.setConfig({
    ortb2: {
        user: {
            eids: [
                {
                    source: "adserver.org",
                    uids: [{ id: "IDFA_VALUE", atype: 3 }]
                }
            ]
        }
    }
});
```

---

## Android GAID

The Google Advertising ID (GAID, also called AAID) is the Android equivalent of IDFA. It provides a resettable, user-controllable identifier for ad targeting.

### SDK Behavior

The Sellwild SDK does not read or store the GAID. The SDK operates without device advertising identifiers by default.

### Passing GAID to Prebid Server

If your app reads the GAID (using the `com.google.android.gms.ads.identifier` library), you can pass it to Prebid Server via the OpenRTB `device.ifa` field when using the direct auction API:

```json
{
  "device": {
    "ua": "Mozilla/5.0 ...",
    "os": "android",
    "osv": "14",
    "ifa": "38400000-8cf0-11bd-b23e-10b96e40000d",
    "lmt": 0
  }
}
```

| Field | Description |
|-------|-------------|
| `device.ifa` | The GAID value. |
| `device.lmt` | Limit Ad Tracking. `0` = tracking allowed, `1` = user opted out. |

### User Opt-Out

On Android, users can reset or disable their advertising ID in **Settings > Privacy > Ads**. When the user opts out:

- `AdvertisingIdClient.Info.isLimitAdTrackingEnabled()` returns `true`.
- Set `device.lmt: 1` in the OpenRTB request. SSPs will suppress personalized bidding.
- On Android 12+, the GAID is replaced with a zeroed-out string when the user opts out.

---

## app-ads.txt

app-ads.txt is a mechanism for app publishers to declare which ad networks are authorized to sell their inventory. It prevents unauthorized reselling of your ad impressions.

### How It Works

1. Your app's store listing URL (e.g., `https://play.google.com/store/apps/details?id=com.aws.android`) links to your developer website.
2. On your developer website, you host an `app-ads.txt` file at the root (e.g., `https://yourcompany.com/app-ads.txt`).
3. SSPs and DSPs crawl this file to verify that the ad request's `app.publisher.id` is authorized to sell inventory for the declared `app.bundle`.

### Requirements

1. **Set `appBundleId` in `SellwildConfig`.** This populates `ortb2.app.bundle`, which SSPs use to look up your app-ads.txt.
2. **Set `appStoreUrl` in `SellwildConfig`.** This populates `ortb2.app.storeurl`, which SSPs use to find your developer website.
3. **Host an app-ads.txt file** on your developer website. Include Sellwild and all SSPs used in your Prebid Server configuration.

### Example app-ads.txt Entry

```
# Sellwild as authorized reseller
sellwild.com, weatherbug, RESELLER

# Direct SSP relationships
appnexus.com, 12345, DIRECT
pubmatic.com, 156209, DIRECT
rubiconproject.com, 98765, DIRECT
openx.com, 540012345, DIRECT
indexexchange.com, 345678, DIRECT
```

### Verification

Without a valid app-ads.txt, some SSPs will not bid on your inventory. Verify your setup:

1. Confirm `appBundleId` and `appStoreUrl` are set in your config.
2. Check that your developer website URL is listed in the app store.
3. Verify the app-ads.txt file is accessible: `curl https://yourcompany.com/app-ads.txt`
4. Use the [IAB app-ads.txt validator](https://iabtechlab.com/compliance-programs/app-ads-txt/) to check for formatting errors.

---

## Data Flow Diagram

The following diagram shows what data leaves the device, where it goes, and what privacy controls apply at each stage.

```
+----------------------------+
|  User's Device             |
|                            |
|  +----------------------+  |
|  | Host App             |  |
|  |                      |  |
|  | CMP collects consent |  |
|  |   - TC string        |  |
|  |   - GPP string       |  |
|  |   - US Privacy       |  |
|  |                      |  |
|  | ATT prompt (iOS)     |  |
|  |   - IDFA (if auth'd) |  |
|  |                      |  |
|  +----------+-----------+  |
|             |               |
|  +----------v-----------+  |
|  | Sellwild SDK         |  |
|  |                      |  |        What leaves the device:
|  | Constructs OpenRTB   |  |        +---------------------------------+
|  | bid request:         |  |        | app.bundle (app ID)             |
|  |   - app identity     +---------->| app.storeurl                    |
|  |   - device UA, OS    |  |        | device.ua (user agent)          |
|  |   - ad sizes         |  |        | device.os, device.osv           |
|  |   - consent signals  |  |        | imp[].banner.format (ad sizes)  |
|  |   - NO personal data |  |        | regs.ext.gdpr (0 or 1)          |
|  |     stored by SDK    |  |        | user.ext.consent (TC string)    |
|  +----------------------+  |        | regs.ext.us_privacy (if set)    |
|                            |        | regs.gpp (if GPP enabled)       |
+----------------------------+        | device.ifa (only if app passes) |
                                      +-----------+---------------------+
                                                  |
                                                  v
                              +-------------------+-------------------+
                              |  prebid.sellwild.com                  |
                              |  (Prebid Server)                      |
                              |                                       |
                              |  Privacy enforcement:                 |
                              |  - Checks regs.ext.gdpr               |
                              |  - Validates TC string vendor consent  |
                              |  - Suppresses non-consented bidders    |
                              |  - Forwards us_privacy / GPP to SSPs  |
                              |                                       |
                              |  Does NOT:                            |
                              |  - Store user data                    |
                              |  - Create user profiles               |
                              |  - Perform cross-session tracking     |
                              +---+----------+----------+-------------+
                                  |          |          |
                                  v          v          v
                            +---------+ +--------+ +-------+
                            | AppNexus| |PubMatic| | IX    |  ... SSPs
                            |         | |        | |       |
                            | Receives| |Receives| |Receive|
                            | bid req | |bid req | |bid req|
                            | with    | |with    | |with   |
                            | consent | |consent | |consent|
                            | signals | |signals | |signal |
                            +---------+ +--------+ +-------+
```

### Data Not Collected by the SDK

The Sellwild SDK does not read, store, or transmit:

- Device advertising identifiers (IDFA, GAID) -- unless the host app explicitly passes them
- Location data (GPS coordinates)
- Contact information
- Browsing history
- App usage data outside the ad session
- Any data written to the device filesystem

### Data Retention

- **Prebid Server:** Auction requests are processed in real-time and not persisted. Per-bidder response telemetry is aggregated for monitoring (no PII).
- **Sellwild Analytics:** Event data (impressions, clicks) is retained for reporting. Events include zone ID, partner code, and session ID -- no user-level PII.
- **SSPs:** Each SSP has its own data retention policy. Consent signals in the bid request govern what SSPs are permitted to store.
