#!/usr/bin/env bash
# The SDK testing gate: type checks, lint, the print gate and the contracts
# checks, in one command. TESTING.md ("Gate") has the steps and their times.
#
#   bash scripts/gate.sh               --fast (the default): no device, no coverage, about 45s warm
#   bash scripts/gate.sh --full        --fast, then Android Lint, every platform's coverage
#                                      (one at a time), the compiler-warnings ratchets and
#                                      the 95% coverage check
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
# after the iOS coverage step. swift-typecheck builds without a simulator.

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

GRADLE='android/gradlew -p android --console=plain'
GATE_GRADLE_STOP='android/gradlew -p android --stop'
GATE_IOS_STOP='xcrun simctl shutdown all'

#    id                   mode kind      native  needs        command
# Type checks. A failure here skips the coverage steps.
step tsgo-core            fast typecheck -       -            'npm --prefix core run --silent typecheck'
step tsgo-react-native    fast typecheck -       -            'npm --prefix react-native run --silent typecheck'
step flutter-analyze      fast typecheck -       -            'cd flutter && flutter analyze --fatal-infos --fatal-warnings'
# Compiles SellwildSDK and its tests for the iOS Simulator, in ios.sh's derived
# data (warm 5-7s, cold about 30s). No simulator boots.
step swift-typecheck      fast typecheck xcode   -            'bash scripts/lint/swift-typecheck.sh'
# Lint. Each baseline sits next to its config; a new finding fails.
step eslint-core          fast lint      -       -            'npm --prefix core run --silent lint'
step eslint-react-native  fast lint      -       -            'npm --prefix react-native run --silent lint'
step lint-rules-test      fast lint      -       -            'node --test --test-reporter=dot contracts/test/lint-rules.test.mjs'
step swiftlint            fast lint      -       -            'bash scripts/lint/swiftlint.sh'
step swift-lint-tests     fast lint      -       -            'node --test --test-reporter=dot scripts/lint/swift-warnings.test.mjs scripts/lint/swiftlint-config.test.mjs scripts/lint/swiftlint-baseline.test.mjs'
step kotlin-warnings-test fast lint      -       -            'node --test --test-reporter=dot scripts/lint/kotlin-warnings.test.mjs'
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
# The other platforms' coverage, one at a time.
step core-coverage        full coverage  -       -            'npm --prefix core run --silent coverage:summary'
step flutter-coverage     full coverage  flutter -            'bash scripts/coverage/flutter.sh'
step ios-coverage         full coverage  ios     -            'bash scripts/coverage/ios.sh'
# Reads the log and .dia files ios.sh just left; refuses a stale log.
step swift-warnings       full warnings  -       ios-coverage 'node scripts/lint/swift-warnings.mjs'
step coverage-thresholds  full coverage  -       -            'node tools/coverage-gate.mjs --expect core,react-native,flutter,android,ios'

gate_main "$@"
