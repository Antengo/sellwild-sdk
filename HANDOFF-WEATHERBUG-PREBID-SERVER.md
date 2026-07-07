# Handoff: WeatherBug Ads Not Rendering — Prebid Server Crash

**Date:** June 30, 2026  
**Status:** BLOCKED — Prebid Server crashing on startup  
**Priority:** Critical (WeatherBug partner integration)

---

## Summary

WeatherBug iOS app (TestFlight build 6.4.0) is not rendering ads. After extensive debugging, the root cause has been identified as an **architectural mismatch** between the iOS SDK (Prebid Mobile) and Prebid Server configuration.

**The core problem:**
1. iOS SDK uses Prebid Mobile's `BannerView(configID:)` API, which **always** sends `storedrequest.id` in auction requests
2. Prebid Server crashes on startup when filesystem `stored_requests` is enabled (exit code 2, glog library crash)
3. When `stored_requests` is disabled, server rejects SDK requests with "No stored imp found" error

---

## Current State

### Prebid Server (ECS)
- **Cluster:** `prebid-cluster`
- **Service:** `prebid-server-service`
- **Status:** 0 running / 1 desired — **container keeps crashing**
- **Task definition:** `prebid-server:33` (PRIMARY), exit code 2
- **Repo:** `~/Documents/sellwild/sellwild-prebid-server`

### Latest config.yaml (HEAD: 8f8ab71)
```yaml
stored_requests:
  filesystem:
    enabled: true
    directorypath: "./stored_requests/data/by_id"
  in_memory_cache:
    type: "unbounded"
    ttl_seconds: 3600
```

### Stored request file exists:
- `stored_requests/data/by_id/weatherbug-mobile-300x250.json`
- Content: `{"banner":{"format":[{"w":300,"h":250}]}}`

### WeatherBug CDN Config (CORRECT)
```json
{
  "MOBILE_ZID": ["weatherbug-mobile-300x250"],
  "GAM": "/21824729475/weatherbug-weatherbug-mobile-300x250",
  "AD_STACK": "both",
  "APP_BUNDLE_ID": "com.aws.weatherbug.pro"
}
```

---

## What We've Tried

1. **CMS fixes (DONE):**
   - Added `GAM` field to app config schema
   - Changed `MOBILE_ZID` from GAM path to simple zone ID
   - Normalized bidder params to standard Prebid names (IX.siteId, APPNEXUS.placement_id, etc.)
   - All deployed and serving correctly from CDN

2. **GAM setup (DONE):**
   - Created ad unit `/21824729475/weatherbug-weatherbug-mobile-300x250` in Sellwild GAM network
   - Verified via sellwild-gam-api

3. **Prebid Server stored requests (BLOCKED):**
   - Created minimal stored impression file
   - Enabled filesystem stored_requests in config.yaml
   - **Server crashes on startup with exit code 2**
   - glog library crash during initialization — no clear error message in logs

4. **Rollback attempts:**
   - Tried rolling back to previous task definitions (24, 32)
   - All crash because `production` ECR tag was overwritten with broken config
   - Image `f4e4eef0ac33180424020d690b5f9d33f84c113a` is the last known working (stored_requests disabled)

---

## The Architectural Problem

**Prebid Mobile SDK limitation:**
- `BannerView(configID:)` always sends `ext.prebid.storedrequest.id` in auction requests
- There is no alternative Prebid Mobile API to bypass this
- This is fundamental to how Prebid Mobile works

**Options:**
1. **Fix the glog crash** — Figure out why enabling stored_requests causes the container to crash
2. **Modify SDK** — Change iOS/Android SDKs to make direct HTTP requests to Prebid Server instead of using Prebid Mobile's BannerView (significant change)
3. **Use GAM-only** — Set `AD_STACK: "gamOnly"` to bypass Prebid entirely (loses Prebid revenue)

---

## Debugging the glog Crash

The crash is in Go's glog library during initialization. Previous issues:
- `analytics.file.filename: /dev/stdout` caused glog to try creating `/dev/stdout-YYYYMMDD` rotation file (FIXED)
- Relative vs absolute path for stored_requests directory (TRIED both)

Current crash has no clear error message in CloudWatch logs. The container exits with code 2 after glog's `flushDaemon` goroutine starts.

**To investigate:**
1. Check CloudWatch logs for task `4d52ec52327e4d3a9588c44b53d191aa`
2. Try building and running Prebid Server locally with same config
3. Check if PBS-Go has specific requirements for stored_requests directory structure

---

## Key Files & Locations

| Item | Location |
|------|----------|
| Prebid Server repo | `~/Documents/sellwild/sellwild-prebid-server` |
| Sellwild SDK repo | `~/Documents/sellwild/sellwild-sdk` |
| Widget/CMS repo | `~/Documents/sellwild/sellwild-widget` |
| GAM API repo | `~/Documents/sellwild/sellwild-gam-api` |
| iOS demo app | `sellwild-sdk/samples/feed-demo-ios` |
| WeatherBug config | `sellwild-widget/app/weatherbug-weatherbug.md` |
| Prebid Server config | `sellwild-prebid-server/config.yaml` |
| Stored impressions | `sellwild-prebid-server/stored_requests/data/by_id/` |

---

## AWS Resources

- **ECS Cluster:** `prebid-cluster` (us-east-1)
- **ECS Service:** `prebid-server-service`
- **ECR Repo:** `457870823482.dkr.ecr.us-east-1.amazonaws.com/prebid-server`
- **CloudWatch Logs:** `/ecs/prebid-server`
- **CloudFront (CDN):** `E2I8MYVEM6ZX5R`
- **S3 (Maven):** `s3://maven.sellwild.com/releases/com/sellwild/`

---

## Suggested Skills

- `native-first-mobile` — SDK architecture and native ad rendering
- `diagnosing-bugs` — For debugging the glog crash

---

## Immediate Next Steps

1. **Get Prebid Server running again:**
   - Either fix the glog crash with stored_requests enabled
   - Or deploy image `f4e4eef0ac33180424020d690b5f9d33f84c113a` (stored_requests disabled) as a temporary measure

2. **If stored_requests can't be enabled:**
   - Consider modifying SDK to bypass Prebid Mobile's BannerView
   - Or switch WeatherBug to `AD_STACK: "gamOnly"` temporarily

3. **Verify end-to-end once server is stable:**
   - Force quit TestFlight app
   - Check Console.app for SDK debug logs
   - Confirm auctions hitting Prebid Server in CloudWatch

---

## People

- **Sandeep Kushwah** — WeatherBug iOS engineer, has TestFlight access
- **Bharat Kudale** — WeatherBug iOS build lead, confirmed ads ARE showing for US locations (as of yesterday)
- **Signal (Ryan)** — Sellwild lead, frustrated with debugging circles

---

## Notes

User explicitly instructed: **Do not modify the Swift SDK** — any fixes should be at CMS or server level if possible.

Bharat mentioned yesterday that "ads ARE showing for US locations" in the TestFlight build. This may indicate the issue is intermittent or location-dependent. Worth confirming current state with Sandeep before assuming everything is broken.
