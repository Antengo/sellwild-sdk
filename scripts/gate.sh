#!/usr/bin/env bash
# The SDK testing gate: type checks, lint, the print gate and the contracts
# checks, in one command. TESTING.md ("Gate", "E2E") has the steps and their times.
#
#   bash scripts/gate.sh               --fast (the default): no device, no coverage, about 55s warm
#   bash scripts/gate.sh --full        --fast, then Android Lint, the Android sample's lint,
#                                      every platform's coverage (one at a time), the
#                                      React Native bridge compiles, the compiler-warnings
#                                      ratchets and the 95% coverage check
#   bash scripts/gate.sh --e2e         the sample apps' e2e only: scripts/e2e/run.sh for
#                                      each app, one at a time (about 10 min warm).
#                                      Never part of --fast or --full.
#   bash scripts/gate.sh --only a,b    just those steps, in gate order
#   bash scripts/gate.sh --list        the step ids, modes and commands
#
# Runs from any directory. Every step runs, even after a failure; the table at
# the end shows each result and the exit status is 1 when any step failed.
# After a failed type check the coverage steps are skipped.
#
# Machine rules: steps run one at a time, so there is one native build at
# most; vitest runs at most 2 workers and Gradle 2 workers; the Gradle daemon
# is stopped after the last Android step, and every simulator is shut down
# after the iOS coverage step. swift-typecheck and rn-bridge-ios build without
# a simulator. The rn-bridge steps and each e2e step take the native lock
# themselves (scripts/e2e/lib/lock.sh), and each e2e step shuts its device
# down before it ends.

set -euo pipefail

GATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_SCRIPT="$GATE_ROOT/scripts/gate.sh"
cd "$GATE_ROOT"
# shellcheck source=../tools/gate-lib.sh
source "$GATE_ROOT/tools/gate-lib.sh"

# Worker caps (vitest reads these for the runs scripts/coverage/ts.mjs spawns).
export VITEST_MAX_FORKS="${VITEST_MAX_FORKS:-2}" VITEST_MAX_THREADS="${VITEST_MAX_THREADS:-2}"
case " ${GRADLE_OPTS:-} " in
  *org.gradle.workers.max=*) ;;
  *) export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.workers.max=2" ;;
esac
# AGP 8.7, detekt and Robolectric need JDK 17 (found as scripts/coverage/android.sh does).
is_jdk17() { [ -x "$1/bin/java" ] && "$1/bin/java" -version 2>&1 | grep -q 'version "17'; }
if ! is_jdk17 "${JAVA_HOME:-}"; then
  for candidate in "$(/usr/libexec/java_home -v 17 2>/dev/null || true)" /Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home; do
    if [ -n "$candidate" ] && is_jdk17 "$candidate"; then export JAVA_HOME="$candidate"; break; fi
  done
fi

# The Android sample has no local.properties, so Gradle finds the Android SDK
# through ANDROID_HOME (android/ has local.properties).
if [ -z "${ANDROID_HOME:-}" ]; then export ANDROID_HOME="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"; fi

GRADLE='android/gradlew -p android --console=plain'
SAMPLE_GRADLE='samples/feed-demo-android/gradlew -p samples/feed-demo-android --console=plain'
GATE_GRADLE_STOP='android/gradlew -p android --stop'
GATE_IOS_STOP='xcrun simctl shutdown all'

#    id                   mode kind      native  needs        command
# Type checks. A failure here skips the coverage steps.
step tsgo-core            fast typecheck -       -            'npm --prefix core run --silent typecheck'
step tsgo-react-native    fast typecheck -       -            'npm --prefix react-native run --silent typecheck'
# Compiles SellwildSDK and its tests for the iOS Simulator, in ios.sh's derived
# data (warm 5-7s, cold about 30s). No simulator boots.
step swift-typecheck      fast typecheck xcode   -            'bash scripts/lint/swift-typecheck.sh'
# Lint. Each baseline sits next to its config; a new finding fails.
step eslint-core          fast lint      -       -            'npm --prefix core run --silent lint'
step eslint-react-native  fast lint      -       -            'npm --prefix react-native run --silent lint'
step lint-rules-test      fast lint      -       -            'node --test --test-reporter=dot contracts/test/lint-rules.test.mjs scripts/lint/eslint-config.test.mjs'
step swiftlint            fast lint      -       -            'bash scripts/lint/swiftlint.sh'
step swift-lint-tests     fast lint      -       -            'node --test --test-reporter=dot scripts/lint/swift-warnings.test.mjs scripts/lint/swiftlint-config.test.mjs scripts/lint/swiftlint-baseline.test.mjs'
step kotlin-warnings-test fast lint      -       -            'node --test --test-reporter=dot scripts/lint/kotlin-warnings.test.mjs'
# The sample apps' own checks (their Swift is in swiftlint above). Kind lint, so
# a failure here never skips the SDK's coverage steps.
step tsgo-sample-rn       fast lint      -       -            'npm --prefix samples/demo-app run --silent typecheck'
step eslint-sample-rn     fast lint      -       -            'npm --prefix samples/demo-app run --silent lint -- --max-warnings 0'
# Contracts: the print gate, every contract file against its schema, the contracts tests.
step print-gate           fast check     -       -            'node contracts/scripts/print-gate.mjs'
step contracts-validate   fast check     -       -            'node contracts/scripts/validate.mjs'
step contracts-test       fast check     -       -            'npm --prefix contracts test --silent -- --test-reporter=dot'
step coverage-gate-test   fast check     -       -            'node --test --test-reporter=dot tools/coverage-gate.test.mjs'
# Gradle, back to back on one daemon: detekt (warm about 20s) in --fast, the rest in --full.
step detekt-android       fast lint      gradle  -            "$GRADLE detektAll"
step android-lint         full lint      gradle  -            "$GRADLE lintDebug"
step android-coverage     full coverage  gradle  -            'bash scripts/coverage/android.sh'
step kotlin-warnings      full warnings  gradle  -            'node scripts/lint/kotlin-warnings.mjs'
# The Android sample: the SDK to mavenLocal (the sample takes it only from
# there), then detekt with the SDK's rules and Android Lint on the sample.
step sample-android-lint  full lint      gradle  -            "$GRADLE publishReleasePublicationToMavenLocal && $SAMPLE_GRADLE :app:detekt :app:detektDebug :app:lintDebug"
# The React Native bridge, compiled inside samples/demo-app against the SDK as
# checked out: Kotlin last in the Gradle row (the script stops both Gradle
# versions), then Swift (an xcode step: no simulator).
step rn-bridge-android    full check     gradle  -            'bash scripts/rn/compile-bridge-android.sh'
step rn-bridge-ios        full check     xcode   -            'bash scripts/rn/compile-bridge-ios.sh'
# The other platforms' coverage, one at a time.
step core-coverage        full coverage  -       -            'npm --prefix core run --silent coverage:summary'
step ios-coverage         full coverage  ios     -            'bash scripts/coverage/ios.sh'
# Reads the log and .dia files ios.sh just left; refuses a stale log.
step swift-warnings       full warnings  -       ios-coverage 'node scripts/lint/swift-warnings.mjs'
step coverage-thresholds  full coverage  -       -            'node tools/coverage-gate.mjs --expect core,react-native,android,ios'

# The e2e steps (mode e2e), one per app in `scripts/e2e/run.sh --list`, so a
# new app is picked up without an edit here. They are declared only for
# --e2e, --only and --list: gate_main's --full runs every declared step.
# run.sh takes the native lock for each app's whole session (build to
# shutdown), so the steps are not native ones here. TESTING.md ("E2E").
gate_e2e=0
gate_declare_e2e=0
for arg in "$@"; do
  case "$arg" in
    --e2e) gate_e2e=1; gate_declare_e2e=1 ;;
    --only | --only=* | --list | -h | --help) gate_declare_e2e=1 ;;
  esac
done
E2E_STEPS=""
if [ "$gate_declare_e2e" = 1 ]; then
  for app in $(bash scripts/e2e/run.sh --list); do
    step "e2e-$app"       e2e  check     -       -            "bash scripts/e2e/run.sh $app"
    E2E_STEPS="${E2E_STEPS:+$E2E_STEPS,}e2e-$app"
  done
fi

if [ "$gate_e2e" = 1 ]; then
  if [ $# -ne 1 ]; then
    echo "gate: --e2e takes no other argument (run --fast or --full on its own)" >&2
    exit 2
  fi
  echo "gate --e2e: $E2E_STEPS (TESTING.md, E2E)"
  gate_main --only "$E2E_STEPS"
else
  gate_main "$@"
fi
