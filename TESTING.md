# Testing the SDK quickly

How long each suite takes, the fastest command that proves a change, and how
to check that tests catch real breaks without rerunning everything.

## Gate

One command runs every type check and linter, the print gate and the
contracts checks. `--full` adds coverage on every platform.

```bash
bash scripts/gate.sh                          # --fast (the default): about 30s, no device, no coverage
bash scripts/gate.sh --full                   # --fast plus coverage and the warnings ratchets: about 3 min
bash scripts/gate.sh --only swiftlint,eslint-core
bash scripts/gate.sh --list                   # step ids and commands
```

How it runs:

1. It works from any directory. Each step runs from the repo root through
   `tools/timed.mjs` (suite `gate:<id>`).
2. A failed step does not stop the run. The table at the end shows every
   step, and the exit status is 1 if any step failed.
3. One exception: after a failed type check, the coverage steps are skipped.
4. Steps run one at a time, so there is never more than one native build. A
   Gradle or iOS step first waits while another `xcodebuild` or Gradle build
   runs on the machine (up to `GATE_NATIVE_WAIT` seconds, default 600).
5. vitest runs at most 2 workers and Gradle 2 workers. `JAVA_HOME` is set to a
   JDK 17.
6. The Gradle steps run back to back on one daemon, then `gradlew --stop`
   runs. `xcrun simctl shutdown all` runs after the iOS step.

`--fast`, measured 2026-09-24 (load about 2):

| Step | What it checks | Time |
|---|---|---|
| `tsgo-core`, `tsgo-react-native` | tsgo type check of src and tests | 1s each |
| `flutter-analyze` | `flutter analyze --fatal-infos --fatal-warnings`, strict casts, inference and raw types | 3s |
| `eslint-core`, `eslint-react-native` | ESLint with type info and the house failure rules | 2s each |
| `lint-rules-test` | tests of the house ESLint rules (`contracts/lint/`) | 0.5s |
| `swiftlint` | SwiftLint on `ios/` and the React Native iOS bridge | 0.3s |
| `swift-lint-tests`, `kotlin-warnings-test` | tests of the Swift and Kotlin lint tooling | 1s |
| `print-gate` | FAILURES.md section 11 | 0.3s |
| `contracts-validate` | every contract file against its schema | 0.3s |
| `contracts-test` | `npm --prefix contracts test` | 5s |
| `coverage-gate-test` | tests of `tools/coverage-gate.mjs` | 0.3s |
| `detekt-android` | detekt on `android/` and the React Native Android bridge | 11s; 20-40s after Kotlin changes |
| total | | 29s |

`--full` adds these, in this order (measured 2026-09-24):

| Step | What it runs | Time |
|---|---|---|
| `android-lint` | Android Lint (`lintDebug`) | 18s |
| `android-coverage` | `bash scripts/coverage/android.sh` | 21s |
| `kotlin-warnings` | Kotlin compiler-warnings ratchet (a full recompile) | 24s |
| `core-coverage` | `npm --prefix core run coverage:summary` (core and RN) | 19s |
| `flutter-coverage` | `bash scripts/coverage/flutter.sh` | 13s |
| `ios-coverage` | `bash scripts/coverage/ios.sh` | 64s |
| `swift-warnings` | Swift compiler-warnings ratchet, from the log `ios.sh` just wrote | 0.2s |
| `coverage-thresholds` | `node tools/coverage-gate.mjs`: every `coverage-summary/*.json` gate at 95% lines, branches (regions for iOS) and functions | 0.2s |
| total, with `--fast` | | 189s |

### Baselines

Each linter starts from a checked-in baseline: the findings that existed on
2026-09-24. A new finding fails. A baseline may only shrink. When you fix
baselined findings, shrink the baseline in the same change:

| Tool | Baseline | Shrink it with |
|---|---|---|
| ESLint | `core/eslint-suppressions.json`, `react-native/eslint-suppressions.json` | `npm --prefix core run lint -- --prune-suppressions` (same for `react-native`) |
| SwiftLint | `.swiftlint.baseline.json` | `bash scripts/lint/swiftlint.sh --update` |
| detekt | `android/config/detekt/baseline-*.xml` | `cd android && ./gradlew detektBaseline` |
| Android Lint | `android/config/lint/lint-baseline.xml` | `cd android && ./gradlew updateLintBaselineDebug` |
| Kotlin warnings | `scripts/lint/kotlin-warnings.baseline.json` | `node scripts/lint/kotlin-warnings.mjs --update` |
| Swift warnings | `scripts/lint/swift-warnings.baseline.json` | `node scripts/lint/swift-warnings.mjs --update`, right after `ios.sh` |
| Print gate | `contracts/print-gate.allowlist.json` | `node contracts/scripts/print-gate.mjs --update` |
| tsgo, flutter analyze | none: kept at zero findings | fix the finding |

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
5. SwiftLint's baseline only matches from the checkout's real path, not from a
   copy under `/tmp`.

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
