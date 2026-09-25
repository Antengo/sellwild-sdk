# Testing the SDK quickly

How long each suite takes, the fastest command that proves a change, and how
to check that tests catch real breaks without rerunning everything.

## Gate

One command runs every type check and linter, the print gate and the
contracts checks. `--full` adds coverage on every platform. `--e2e` runs the
sample apps' Maestro e2e (see E2E).

```bash
bash scripts/gate.sh                          # --fast (the default): about 55s warm, no device, no coverage
bash scripts/gate.sh --full                   # --fast plus coverage, the warnings ratchets and the RN bridge: about 4 min
bash scripts/gate.sh --e2e                    # the e2e only, every app one at a time: about 17 min warm
bash scripts/gate.sh --only swiftlint,eslint-core
bash scripts/gate.sh --list                   # step ids, modes and commands
```

How it runs:

1. It works from any directory. Each step runs from the repo root through
   `tools/timed.mjs` (suite `gate:<id>`).
2. A failed step does not stop the run. The table at the end shows every
   step, and the exit status is 1 if any step failed.
3. One exception: after a failed type check, the coverage steps are skipped.
4. Steps run one at a time, so there is never more than one native build. A
   Gradle or Xcode step first waits while another `xcodebuild` or Gradle build
   runs on the machine (up to `GATE_NATIVE_WAIT` seconds, default 600). The
   `rn-bridge-*` steps also take the native lock for their whole run (`pod
   install` and `xcodebuild` on iOS). On a machine shared by several agents,
   run the whole gate under the native lock too; the steps then see it and do
   not take it again.
5. vitest runs at most 2 workers and Gradle 2 workers. `JAVA_HOME` is set to a
   JDK 17.
6. The Gradle steps run back to back on one daemon, then `gradlew --stop`
   runs. `xcrun simctl shutdown all` runs after the iOS coverage step.
   `swift-typecheck` and `rn-bridge-ios` only build, so no simulator boots
   and none is shut down (gate-lib's `xcode` kind).
7. `ANDROID_HOME` defaults to `~/Library/Android/sdk`. The Android sample has
   no `local.properties`, so its Gradle build needs it.
8. The sample steps have kind `lint`. A failed sample check never skips the
   SDK's coverage steps.

`--fast`, measured 2026-09-25 after the origin/main merge, inside the
`--full` run below (load 20-60, other agents busy):

| Step | What it checks | Time |
|---|---|---|
| `tsgo-core`, `tsgo-react-native` | tsgo type check of src and tests | 1s each |
| `swift-typecheck` | `scripts/lint/swift-typecheck.sh`: `xcodebuild build-for-testing` of SellwildSDK and its tests for the simulator, in `ios.sh`'s derived data (`.coverage-tmp/ios-dd`), so the two share one build | 13s (5-7s warm at load 2, 28s cold) |
| `eslint-core`, `eslint-react-native` | ESLint with type info and the house failure rules | 2.5s each |
| `lint-rules-test` | tests of the house ESLint rules (`contracts/lint/`) and of both ESLint configs (`scripts/lint/eslint-config.test.mjs`) | 1s |
| `swiftlint` | SwiftLint on `ios/`, the React Native iOS bridge and the sample apps' Swift (`samples/`), against its baseline | 0.4s |
| `swift-lint-tests`, `kotlin-warnings-test` | tests of the Swift and Kotlin lint tooling, the SwiftLint baseline matcher included | 1s |
| `print-gate` | FAILURES.md section 11 | 0.3s |
| `contracts-validate` | every contract file against its schema | 0.3s |
| `contracts-test` | `npm --prefix contracts test` | 5s |
| `coverage-gate-test` | tests of `tools/coverage-gate.mjs` | 0.3s |
| `tsgo-sample-rn` | tsgo on the React Native sample, `samples/demo-app` (its `typecheck` script; it checks the SDK sources it imports too) | 1s |
| `eslint-sample-rn` | ESLint (`@react-native` config) on `samples/demo-app`, with `--max-warnings 0` | 2s |
| `detekt-android` | detekt on `android/` and the React Native Android bridge | 12s; 20-40s after Kotlin changes |
| total | | 43s (16 steps) |

`--full` adds these, in this order (measured 2026-09-25, load 20-60):

| Step | What it runs | Time |
|---|---|---|
| `android-lint` | Android Lint (`lintDebug`) | 16s |
| `android-coverage` | `bash scripts/coverage/android.sh` | 21s |
| `kotlin-warnings` | Kotlin compiler-warnings ratchet (a full recompile) | 26s |
| `sample-android-lint` | the SDK to mavenLocal, then detekt (the SDK's rules plus the sample's `detekt.yml`) and Android Lint (warnings are errors) on `samples/feed-demo-android` | 30s |
| `rn-bridge-android` | `bash scripts/rn/compile-bridge-android.sh`: the SDK to mavenLocal, then the bridge's Kotlin inside `samples/demo-app`. The last Gradle step: it stops both Gradle versions | 22s (12s warm at load 2, 94s cold) |
| `rn-bridge-ios` | `bash scripts/rn/compile-bridge-ios.sh`: inside the native lock, `pod install` when stale, then `xcodebuild` of the `SellwildSDK-RN` pod target for the simulator. No app, no simulator | 29s after the webview pod left (4s warm, 87s cold) |
| `core-coverage` | `npm --prefix core run coverage:summary` (core and RN) | 18s |
| `ios-coverage` | `bash scripts/coverage/ios.sh` | 70s |
| `swift-warnings` | Swift compiler-warnings ratchet, from the log `ios.sh` just wrote | 0.2s |
| `coverage-thresholds` | `node tools/coverage-gate.mjs`: every `coverage-summary/*.json` gate at 95% lines, branches (regions for iOS) and functions | 0.2s |
| total, with `--fast` | | 277s (26 steps) |

### Baselines

Each linter starts from a checked-in baseline: the findings that existed on
2026-09-24. A new finding fails. A baseline may only shrink. When you fix
baselined findings, shrink the baseline in the same change:

| Tool | Baseline | Shrink it with |
|---|---|---|
| ESLint | `core/eslint-suppressions.json`, `react-native/eslint-suppressions.json` | `npm --prefix core run lint -- --prune-suppressions` (same for `react-native`) |
| SwiftLint | `scripts/lint/swiftlint.baseline.json` | `bash scripts/lint/swiftlint.sh --update` |
| detekt | `android/config/detekt/baseline-*.xml` | `cd android && ./gradlew detektBaseline` |
| Android Lint | `android/config/lint/lint-baseline.xml` | `cd android && ./gradlew updateLintBaselineDebug` |
| Kotlin warnings | `scripts/lint/kotlin-warnings.baseline.json` | `node scripts/lint/kotlin-warnings.mjs --update` |
| Swift warnings | `scripts/lint/swift-warnings.baseline.json` | `node scripts/lint/swift-warnings.mjs --update`, right after `ios.sh` |
| Print gate | `contracts/print-gate.allowlist.json` | `node contracts/scripts/print-gate.mjs --update` |
| tsgo | none: kept at zero findings | fix the finding |
| The sample apps (all their linters) | none: kept at zero findings. `samples/` has no entry in the SwiftLint baseline | fix the finding |

Notes:

1. ESLint also fails (exit 2) when a baselined finding is gone but still
   counted. Run its prune command.
2. `swiftlint.sh --update`, the warnings ratchets and the print gate refuse to
   add findings unless you pass `--allow-increase`. That needs a reviewer.
3. `detektBaseline` and `updateLintBaselineDebug` rewrite the whole file, new
   findings included. Run them only after fixing findings, and check that the
   diff only removes entries.
4. Never re-baseline to get green. Fix the finding, or disable the rule on
   that one line with a reason.
5. The SwiftLint baseline is ours, not SwiftLint's `--baseline` (which broke
   on any added or removed line in a long file, because the size rules put
   the measured number in the reason). `scripts/lint/swiftlint-baseline.mjs`
   matches a finding by file, rule and reason with numbers as `#`, counted
   per key; line numbers and line text do not count. The size rules (file,
   type and function length, complexity, parameter count, line length) also
   keep the measured number: it may stay or shrink, never grow. So a comment
   or a removed line passes, and one more line in a baselined long function
   fails. `file_length` ignores comment-only lines. Two long functions in
   one file are paired by size, so they can trade lines unseen. With no
   baseline file, `--update` needs `--allow-increase`.
6. detekt's `SwallowedException` has no baseline entries: every catch that
   drops its exception fails.
7. ESLint exceptions are per catch, never per file or function: an
   `// eslint-disable-next-line sellwild/<rule> -- FAILURES.md <section>: <why>`
   at the site. `sellwild/disable-reason` fails one without a reason that
   cites FAILURES.md, and `scripts/lint/eslint-config.test.mjs` lists every
   such site in src (a new one needs an entry there) and fails a comment
   that turns every rule off, which `disable-reason` cannot see.

What each check leaves to another (all found by mutation checks, 2026-09-24):

1. TypeScript: `globalThis.console`, `window.console`, `self.console` and
   `global.console` fail `sellwild/no-global-console`, and the print gate.
2. Swift: `Swift.print`, `Foundation.NSLog` and `os.os_log` fail SwiftLint's
   `no_print` and the print gate. Kotlin: `kotlin.io.println` fails the print
   gate.

## E2E

The sample apps' Maestro e2e. `e2e/README.md` has the details: setup, the
flows, the ids, each app, and how to add one.

```bash
bash scripts/gate.sh --e2e                    # every app, one at a time: about 10 min warm
bash scripts/gate.sh --only e2e-ios,e2e-android
bash scripts/e2e/run.sh ios                   # one app, without the gate
bash scripts/e2e/run.sh --list                # the apps
```

What it runs:

1. Each platform has a sample app, "Sellwild Sample", with four tabs: Feed,
   Ads, Listings and Diagnostics. (The Legacy tab went with the WebView
   widget, and the Flutter sample with the Flutter SDK: origin/main 9ff579f,
   df551f7.)
2. `scripts/e2e/run.sh <app>` builds the app, boots the device, installs the
   app, runs its Maestro flows, saves the screenshots and shuts the device
   down.
3. Maestro 2.10.0, from `~/.maestro/bin` (`MAESTRO` picks another). The
   "Setup" part of `e2e/README.md` installs it.
4. The element ids live in `contracts/e2e/ids.json`. `contracts-test` (in
   `--fast`) fails when a flow, a sample or an SDK uses an `sw.*` id that is
   not listed there.

How `--e2e` runs:

1. One step per app, `e2e-<app>`, taken from `run.sh --list`. A new
   `scripts/e2e/apps/<app>.sh` joins the gate with no edit to `gate.sh`.
2. It is never part of `--fast` or `--full`. `--e2e` takes no other argument.
3. Apps run one at a time. A failed app does not stop the run. The table at
   the end shows every app, and the exit status is 1 if any app failed.
4. Each `run.sh` takes the native lock for its whole session, from build to
   shutdown. It shuts the device down even when a flow fails.
5. You can also run the whole gate under the lock. `run.sh` then finds the
   lock among its parent processes and does not take it again. Other agents
   wait for the whole run.
6. It needs Maestro, a JDK 17, Xcode and an iPhone simulator, the Android SDK
   with an AVD, Node and npm, and CocoaPods.
7. Android boots `SELLWILD_ANDROID_AVD` (default `Pixel_5_API_36`, the AVD
   used for the times below). If your default AVD has no room, set
   `SELLWILD_ANDROID_AVD`.
8. It uses live services: the CDN (it answers 403 for the samples' config,
   so the flows expect "fallback"), cache.sellwild.com, Google test ads, prod
   Prebid Server, and prod events under code `sellwild`. When one is down,
   the run fails.

Times per app, whole run from build to shutdown (measured 2026-09-25 after
the origin/main merge, warm caches, load 20-60; first runs from 2026-09-24):

| App | Sample | Device | Warm | First run |
|---|---|---|---|---|
| `ios` | `samples/feed-demo-ios` | iPhone 17, iOS 26.5 | 123s (flow 55s) | not recorded |
| `android` | `samples/feed-demo-android` | `Pixel_5_API_36` | 103s (flow 46s) | not recorded |
| `rn-ios` | `samples/demo-app` | iPhone 17 | 255s (flow 45s) | 549s |
| `rn-android` | `samples/demo-app` | `Pixel_5_API_36` | 137s (flow 41s) | 681s |
| `--e2e`, all four | | | 618s (one measured run) | 30 min or more |

The first runs download Gradle, the NDK, pods and SwiftPM packages. The
first-run total is a sum of the runs above (the warm time where no first run
was recorded), not one measured run.

Output:

1. `e2e/artifacts/<app>/` (git-ignored). Each run of an app wipes its folder
   first.
   1. `screenshots/<flow>-<screen>.png`: one per screen, plus one for each
      failed step.
   2. `maestro.log`: every step with its status.
   3. `report-<flow>.xml`: JUnit.
   4. `build.log`, `device.log`, and `emulator.log` on Android.
   5. `maestro/<flow>/`: Maestro's own output, with the view hierarchy of a
      failed step.
2. Build caches go to `e2e/.cache/` (git-ignored).

## Timings

Every run through `tools/timed.mjs`, and every run of `scripts/coverage/*.sh`,
is logged to `.timings/suites.jsonl` (git-ignored) with its phases and the
machine load at the start. See the history:

```bash
node tools/timings-report.mjs                 # median, p90, last, phase medians per suite
node tools/timings-report.mjs --suite ios     # one suite
node tools/timed.mjs core:test -- npm --prefix core test   # time any command
```

Measured 2026-09-24 on the dev machine (M1, 8 cores, 16 GB), with other work
running:

| Suite | Command | Time |
|---|---|---|
| contracts | `npm --prefix contracts test` | 7s |
| contracts validate | `node contracts/scripts/validate.mjs` | 1s |
| core tests | `npm --prefix core test` | 9s |
| react-native tests | `npm --prefix react-native test` | 7s |
| core + RN coverage | `npm --prefix core run coverage:summary` | 25s |
| type checks (tsgo) | `npm --prefix core run typecheck` | 1s |
| Android tests (no report) | `cd android && ./gradlew testDebugUnitTest` | 20s |
| Android tests + Kover | `bash scripts/coverage/android.sh` | 35s |
| iOS build + tests + coverage | `bash scripts/coverage/ios.sh` | 68s |

When the machine is overloaded (load well over 16), the same runs take 5 to 20
times longer. Most slow runs in the history were contention, not the suites.

## Fastest check per platform

Run the narrowest command while working. Run the full suite once at the end.

| Platform | Narrow command | Time |
|---|---|---|
| core, RN | `cd core && npx vitest run test/api.test.ts --maxWorkers=2` | ~5s |
| contracts | `cd contracts && node --test test/<file>.test.mjs` | ~1-3s |
| Android | `cd android && ./gradlew testDebugUnitTest --tests 'com.sellwild.sdk.SellwildEventQueueTest'` | ~5s warm |
| iOS | `command xcodebuild test -scheme SellwildSDK -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .coverage-tmp/ios-dd -enableCodeCoverage YES -only-testing:SellwildSDKTests/<TestClass>` | ~40-70s |
| iOS, compile only | `bash scripts/lint/swift-typecheck.sh` (the gate's `swift-typecheck`) | 5-7s warm |

Notes:
1. iOS: use `.coverage-tmp/ios-dd` with `-enableCodeCoverage YES`, the same as
   `ios.sh`. A different DerivedData path or coverage setting forces a cold
   rebuild. About 30s of every iOS run is the simulator launching the test
   host, so iOS checks cannot get much faster than that.
2. Android: a comment-only change compiles to the same bytecode, so Gradle
   reuses the last result. Add `--rerun` when you need the tests to run anyway.
3. Coverage instrumentation slows every run. Leave it off except for the final
   coverage run (except iOS, per note 1).

## Checking that tests catch breaks (mutation checks)

Do not rerun the whole suite for every mutation. Use `tools/mutate.mjs`:

1. Write a spec: one entry per mutation, each with the narrowest test command
   that covers the mutated line (the file's own test file or test class).
2. `node tools/mutate.mjs spec.json --out results.json` runs them one at a
   time, each under a timeout, and restores the file after each.
3. A mutation is caught when its narrow test fails. Only mutations that
   SURVIVE the narrow test need a second look: rerun just those with the full
   suite for that platform, in case a test elsewhere catches them.
4. If a run is interrupted (killed agent, stopped workflow), run
   `node tools/mutate.mjs --recover`. It restores every file that still holds
   the exact mutated text and leaves alone any file edited since.

```json
[
  { "id": "M1", "file": "core/src/api.ts", "find": "if (!res.ok)", "replace": "if (false)",
    "test": "cd core && npx vitest run test/api.test.ts --maxWorkers=2" }
]
```

## Keeping the machine usable

1. One native build (Xcode, Gradle) at a time.
2. Never run suites in the background or two at once.
3. Cap vitest at `--maxWorkers=2`, and Gradle at `GRADLE_OPTS=-Dorg.gradle.workers.max=2`.
4. When done: `cd android && ./gradlew --stop`, and `xcrun simctl shutdown all`.
   A shut-down simulator can leave `appstored` spinning a full core; kill it
   if `ps` shows a `RuntimeRoot/.../appstored` process using CPU.
