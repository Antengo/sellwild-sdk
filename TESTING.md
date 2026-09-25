# Testing the SDK quickly

How long each suite takes, the fastest command that proves a change, and how
to check that tests catch real breaks without rerunning everything.

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
| Flutter tests + coverage | `bash scripts/coverage/flutter.sh` | 16s |
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
| Flutter | `cd flutter && flutter test test/sellwild_api_test.dart` | ~7s |
| Android | `cd android && ./gradlew testDebugUnitTest --tests 'com.sellwild.sdk.SellwildEventQueueTest'` | ~5s warm |
| iOS | `command xcodebuild test -scheme SellwildSDK -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .coverage-tmp/ios-dd -enableCodeCoverage YES -only-testing:SellwildSDKTests/<TestClass>` | ~40-70s |

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

1. One native build (Xcode, Gradle, Flutter) at a time.
2. Never run suites in the background or two at once.
3. Cap vitest at `--maxWorkers=2`, and Gradle at `GRADLE_OPTS=-Dorg.gradle.workers.max=2`.
4. When done: `cd android && ./gradlew --stop`, and `xcrun simctl shutdown all`.
   A shut-down simulator can leave `appstored` spinning a full core; kill it
   if `ps` shows a `RuntimeRoot/.../appstored` process using CPU.
