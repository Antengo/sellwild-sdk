# Sample app e2e (Maestro)

## What this is

1. Each platform has a sample app named "Sellwild Sample".
2. It has five tabs: Feed, Ads, Listings, Diagnostics, Legacy.
3. Maestro flows open every tab and check each screen's key element by id.
4. The ids live in `contracts/e2e/ids.json`. Add an id there before you use it. Never rename one.
5. `scripts/e2e/run.sh <app>` runs one app from build to shutdown.

## Setup

1. Maestro 2.10.0, once per machine:

   ```sh
   curl -fsSL https://get.maestro.mobile.dev -o /tmp/maestro-install.sh
   PATH="$HOME/.maestro/bin:$PATH" MAESTRO_VERSION=2.10.0 bash /tmp/maestro-install.sh
   ~/.maestro/bin/maestro --version   # 2.10.0
   ```

   The `PATH` prefix stops the installer from editing your shell profiles.
2. A JDK 17. `run.sh` finds it, or set `JAVA_HOME`.
3. iOS: Xcode 26.5. `xcodegen` only to regenerate a sample project.

## Run

1. One app: `bash scripts/e2e/run.sh ios`.
2. The apps: `bash scripts/e2e/run.sh --list`.
3. It builds, boots the device, installs, runs the app's flows, copies the screenshots, then shuts the device down.
4. All of that runs inside one call of the native lock (`SELLWILD_NATIVE_LOCK`). One native build or booted device at a time.
5. Exit status: 0 all flows passed, 1 a flow failed, 2 setup failed (unknown app, no Maestro, build, boot or install).
6. `SELLWILD_E2E_NO_BUILD=1` reuses the last build.
7. Output goes to `e2e/artifacts/<app>/` (gitignored):
   1. `screenshots/<flow>-<screen>.png`: one per screen, plus a screenshot of any failed step.
   2. `maestro.log`: Maestro's summary and every step with its status.
   3. `report-<flow>.xml`: JUnit.
   4. `build.log`, `device.log`.
   5. `maestro/<flow>/`: Maestro's own output (commands, logs, the view hierarchy of a failed step).
8. Build caches go to `e2e/.cache/` (gitignored).

## The common subflows (`e2e/maestro/common/`)

1. `launch.yaml`: launch with `clearState`, wait for the tab bar.
2. `no-crash.yaml`: no crash or error dialog, and the tab bar is still on screen. Every screen runs it.
3. `feed.yaml`: the feed list and at least one `sw.listing.card`. Screenshot `feed`.
4. `ads.yaml`: the 320x50 and 300x250 slots and their measured sizes. Fill is not checked. Screenshot `ads`.
5. `listings.yaml`: at least one card and status `<n> listings, load 1`. Refresh, then `load 2`. Screenshot `listings`.
6. `diagnostics.yaml`: SDK version, `sellwild / sellwild-sample`, config source `fallback`, failures. Screenshot `diagnostics`.
7. `legacy.yaml`: the title "Legacy WebView widget (deprecated)" and the WebView container only. Screenshot `legacy`.

Flags each app's flow sets in `env` (the string `"true"` turns one on):

1. `APP_ID`: the bundle id or application id.
2. `FEED_AD_ROWS`: the SDK feed sets `sw.feed.ad` on its ad rows. The feed flow then scrolls to one.
3. `NATIVE_AD`: the platform has a public native ad view. The ads flow checks `sw.ad.native`.
4. `HOUSE_AD`: the platform has a public house ad view. The ads flow checks `sw.ad.house`.
5. `FAILURE_SINK`: the app can list the failure codes the SDK reported. Diagnostics must then show `config.fetch.http`. Otherwise it must show "not available on this platform".

## Why "fallback" and config.fetch.http

1. Every sample uses partner code `sellwild` and slug `sellwild-sample`.
2. The CDN has no app config for that slug. It answers 403.
3. So the SDK keeps its built-in config and Google's test ad units, and reports `config.fetch.http` once a launch. That is expected.
4. Listings come from `https://cache.sellwild.com/listings-img-data-sm-avif-fandom`, passed as `listingsUrl`.
5. Events still go to events.sellwild.com under code `sellwild`.

## Apps

### ios

1. App: `samples/feed-demo-ios`. Project `SellwildSample.xcodeproj` (xcodegen), scheme `SellwildSample`, bundle id `com.sellwild.sample`.
2. The SDK comes from the repo's root `Package.swift`, so the app tests the SDK as checked out.
3. Flow: `e2e/maestro/ios/sample.yaml`. Flags: `FEED_AD_ROWS` on, `NATIVE_AD` on, `HOUSE_AD` off, `FAILURE_SINK` off.
4. Device: the iPhone that `scripts/coverage/ios.sh` picks (iPhone 17, iOS 26.5 here). Set `SELLWILD_IOS_SIM_ID` to pick another.
5. Time: about 3 minutes (build 20s warm, boot 12s, flow 75s). The first build also fetches the SwiftPM packages.
6. Not on iOS:
   1. House ad: there is no public house ad view. House backfill runs inside `SellwildAdView` on a no-fill.
   2. Failure codes: there is no public failure sink. The screen shows the public `SellwildFailures.context` instead.
7. WebViews: Maestro can see into a WKWebView on iOS: the GAM test creative's iframe and images show in the hierarchy. The Legacy widget's content was not checked. The flows check only the container.

## Add an app

1. Write `scripts/e2e/apps/<app>.sh`. Copy `apps/ios.sh`. Set `E2E_APP_ID` and `E2E_FLOWS`. Define `e2e_build`, `e2e_boot`, `e2e_install` and `e2e_shutdown`.
2. For an iOS simulator, use `scripts/e2e/lib/ios-sim.sh`. Put helpers for another device kind in a new `scripts/e2e/lib/<kind>.sh`. `run.sh` sources every `lib/*.sh`.
3. `e2e_shutdown` must shut the device down (`xcrun simctl shutdown all`, `adb emu kill`). Stop Gradle there too (`./gradlew --stop`).
4. Write `e2e/maestro/<app>/<flow>.yaml`. Set `appId`, `env` (`APP_ID` and the flags), then run the common subflows.
5. Add new ids to `contracts/e2e/ids.json` first. `contracts/test/e2e-ids.test.mjs` fails on an unlisted id.
6. Add a section for the app above.
