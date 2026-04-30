# Sellwild SDK — Weatherbug Deal TODO

Everything needed to close the $10M Weatherbug deal.

---

## 1. Prebid Server Telemetry Pipeline

The demo must show live auction data flowing from PBS to a dashboard.

- [x] Verify InfluxDB integration is active on `prebid.sellwild.com`
  - Config has `metrics.influxdb` — confirm data is landing in InfluxDB Cloud
  - Endpoint: `us-east-1-1.aws.cloud2.influxdata.com`
  - Org: `d56fc5d9affa530e`, bucket: `prebid_metrics`
  - ✅ Verified — Athena tables (counter, gauge, histogram, meter, timer) have data back to Sep 2025
- [x] Instrument auction requests with tracking fields (partner code, app bundle, ad size, bidder, CPM, fill/no-fill)
  - ✅ Enabled `analytics.log` in PBS config — every auction logged as structured JSON to CloudWatch
- [x] Confirm per-bidder response times, bid prices, and error rates are captured
  - ✅ Full OpenRTB response logged: responsetimemillis, seatbid with CPMs, ext.errors per bidder
- [ ] Add impression and click event tracking from the SDK to the events API
- [x] Validate data pipeline end-to-end: SDK → PBS auction → InfluxDB → queryable
  - ✅ Demo app → PBS → CloudWatch Logs → Dashboard (per-auction deep-link works)
  - ✅ PBS → Athena (aggregate metrics: counter/histogram/timer tables queryable)

---

## 2. Sellwild Admin Dashboard

A partner-facing portal to view auction data in near real-time.

- [x] Build admin dashboard (React + Tailwind, match CMS design system)
  - ✅ Next.js app in `dashboard/` — DM Sans, dark theme, Recharts visualizations
- [x] Dashboard views:
  - [x] Real-time auction feed (last 100 auctions, auto-refresh)
    - ✅ `/auctions` — live feed from CloudWatch with source, bidders, winner, CPM
  - [x] CPM by SSP (bar chart — which bidders are winning and at what price)
    - ✅ Overview page — Athena histogram table
  - [ ] Fill rate by ad size (320x50, 300x250, etc.)
  - [x] Response time by SSP (latency monitoring)
    - ✅ Overview page — latency trend chart + per-bidder breakdown
  - [x] Error rate by SSP (which bidders are failing and why)
    - ✅ Bidder summary table with fill/error rates
  - [ ] Revenue summary (estimated daily/weekly/monthly)
- [ ] Filtering: by partner code, date range, ad size, SSP
- [ ] Export: CSV/PDF report generation
- [ ] Deploy to `admin.sellwild.com` or similar

---

## 3. Reporting & Diagnostics

Weatherbug needs to know we can diagnose and fix issues with data.

- [ ] Automated alerting: if fill rate drops below threshold, notify
- [ ] Per-SSP health check: detect when a bidder stops responding
- [x] Auction log viewer: drill into a specific auction by ID, see full OpenRTB request/response
  - ✅ `/auctions/[auctionId]` — per-slot bidder breakdown, latency chart, raw JSON, deep-linked from demo app
- [ ] GDPR compliance report: show which auctions were blocked by consent enforcement
- [ ] Generate sample weekly partner report (PDF) showing:
  - Total impressions, fill rate, avg CPM, revenue by SSP
  - Top performing ad sizes
  - Latency trends
  - Recommendations

---

## 4. Remotion Slideshow — Sellwild SDK Pitch

A polished video presentation for the Weatherbug meeting.

- [ ] Remotion project setup (`sellwild-sdk-pitch`)
- [ ] Slides:
  - [ ] Title: "Sellwild SDK — Server-Side Header Bidding for Mobile Apps"
  - [ ] Problem: "You're managing 40+ SDK integrations"
  - [ ] Solution: "One SDK. All your demand. Sub-200ms auctions."
  - [ ] Architecture diagram (animated version of the docs diagram)
  - [ ] Live demo footage: simulator showing listings + ads + auction panel
  - [ ] Prebid Server: "400+ SSP adapters, your existing demand partners"
  - [ ] Auction transparency: show the bidder response time panel
  - [ ] Revenue projection: "$10M opportunity"
  - [ ] Pilot proposal: "5% traffic, 30 days, zero risk"
  - [ ] Call to action: "Give us your seat IDs"
- [ ] Export as MP4 (1080p)
- [ ] Duration: 2-3 minutes

---

## 5. Mastra Demo Video MP4

Automated demo video showing the SDK in action.

- [ ] Browser automation script: walk through the demo app on simulator
  - Scroll through listings, show ads loading, tap "Run Again" on auction panel
- [ ] Record GIF/video of the full demo flow
- [ ] Add ElevenLabs voiceover narration explaining each screen
- [ ] Compose with Remotion: demo footage + voiceover + title cards
- [ ] Export as MP4 (1080p)
- [ ] Duration: 60-90 seconds

---

## 6. Documentation — Primetime Ready

The docs at `sdk.sellwild.com` must be flawless.

- [ ] Review all 14 pages for accuracy against Lawrence's codebase
- [ ] Fix any code examples that reference outdated APIs
- [ ] Verify no dead links (VitePress build passes clean)
- [ ] Architecture diagram component — no clipping, responsive
- [ ] Dark mode — verify all pages render correctly
- [ ] Mobile responsive — check on phone-width viewport
- [ ] Redeploy to `sdk.sellwild.com` after all fixes
- [ ] Update docs PR (#3) on `Antengo/sellwild-sdk`

---

## 7. SDK Fixes PR — Merge Ready

PR #2 on `Antengo/sellwild-sdk` must be clean.

- [ ] All 8 bug fixes verified against Lawrence's test suite
- [ ] Run Lawrence's unit tests: `SellwildConfigTest.kt`, `SellwildConfigTests.swift`, `sellwild_config_test.dart`
- [ ] Verify no regressions in existing sample apps
- [ ] Get Lawrence's review and merge

---

## Priority Order

1. **Telemetry pipeline** — without data, we can't show value
2. **Admin dashboard** — Weatherbug needs to see we have operational control
3. **Documentation** — must be primetime before sharing with their engineers
4. **SDK fixes PR** — merge so the repo is clean
5. **Remotion slideshow** — for the pitch meeting
6. **Demo video** — leave-behind after the meeting
7. **Reporting** — deliver in the first week of the pilot

---

## Open PRs

- [#2 — SDK Bug Fixes](https://github.com/Antengo/sellwild-sdk/pull/2) — 8 critical fixes, 9 files
- [#3 — Documentation + Docs Site](https://github.com/Antengo/sellwild-sdk/pull/3) — 26 files, 15K lines

---

## Key Resources

| Resource | Location |
|----------|----------|
| SDK Repo | `github.com/Antengo/sellwild-sdk` |
| Local Clone | `/Documents/sellwild/sellwild-sdk/` |
| Demo App | `/Desktop/SellwildDemo/` |
| Prebid Server | `prebid.sellwild.com` (us-west-1 ECS) |
| PBS Config S3 | `prebid-server-containerimageconfigfilesbucketb8caf-mdciqkuhyars` |
| InfluxDB | `us-east-1-1.aws.cloud2.influxdata.com` |
| Docs Site | `sdk.sellwild.com` |
| CMS Design System | `/Documents/sellwild/sellwild-cms-design/` |
| Widget Repo | `/Documents/sellwild/sellwild-widget/` |
| Weatherbug app-ads.txt | `weatherbug.com/app-ads.txt` (637 lines, 40+ SSPs) |
| Weatherbug Bundle ID | `com.aws.android` |
