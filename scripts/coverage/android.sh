#!/usr/bin/env bash
# Android SDK coverage: runs the JVM unit tests (JUnit 4 on the JUnit Platform,
# plus Robolectric) with Kover, validates the contract payloads the tests
# emitted (when the contracts validator exists), and writes
# coverage-summary/android.json (A10).
#
# Usage: bash scripts/coverage/android.sh
#   JAVA_HOME=<jdk 17>          used when it is a JDK 17; otherwise the script finds one
#   SELLWILD_CONTRACT_OUT=<dir> contract output root; tests write <dir>/android
#   COVERAGE_ENFORCE=1          also fail when the gate is under 95%
#
# Exit status: the Gradle status if the build or tests failed (no summary is
# written), else 1 if contract validation failed (a payload did not match its
# schema, or the tests emitted none), else the summary's status
# (non-zero only on a summary error, or on a missed gate with COVERAGE_ENFORCE=1).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE="$ROOT/android"
XML="$MODULE/build/reports/kover/reportDebug.xml"
RESULTS="$MODULE/build/test-results/testDebugUnitTest"
SUMMARY="$ROOT/coverage-summary/android.json"
VALIDATOR="$ROOT/contracts/scripts/validate.mjs"
# ContractEmitter (via android/build.gradle.kts) and validate.mjs both write and
# read $SELLWILD_CONTRACT_OUT/android when it is set. Made absolute here, from
# the caller's directory: Gradle would resolve a relative path from android/.
if [ -n "${SELLWILD_CONTRACT_OUT:-}" ]; then
  mkdir -p "$SELLWILD_CONTRACT_OUT" || exit 1
  SELLWILD_CONTRACT_OUT="$(cd "$SELLWILD_CONTRACT_OUT" && pwd)" || exit 1
  export SELLWILD_CONTRACT_OUT
fi
CONTRACT_OUT="${SELLWILD_CONTRACT_OUT:-$ROOT/contracts/out}/android"
DEFAULT_JDK17="/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home"

is_jdk17() { [ -x "$1/bin/java" ] && "$1/bin/java" -version 2>&1 | grep -q 'version "17'; }

# AGP 8.7 and Robolectric's SDK 35 jar both need JDK 17.
if ! is_jdk17 "${JAVA_HOME:-}"; then
  candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  if [ -n "$candidate" ] && is_jdk17 "$candidate"; then
    JAVA_HOME="$candidate"
  elif is_jdk17 "$DEFAULT_JDK17"; then
    JAVA_HOME="$DEFAULT_JDK17"
  else
    echo "android.sh: no JDK 17 found. Set JAVA_HOME to a JDK 17." >&2
    exit 127
  fi
fi
export JAVA_HOME

cd "$MODULE" || exit 1

# Stale output would be counted as this run's: an old report inflates coverage,
# old emitted payloads get validated again. Removing the payload dir (a test
# task output) also makes Gradle rerun the tests instead of reusing them.
rm -f "$XML"
rm -rf "$CONTRACT_OUT"

./gradlew testDebugUnitTest koverXmlReportDebug koverHtmlReportDebug
gradle_status=$?

if [ "$gradle_status" -ne 0 ] || [ ! -s "$XML" ]; then
  echo "android.sh: Gradle exit $gradle_status; no coverage summary written (reports: $MODULE/build/reports/tests/testDebugUnitTest)." >&2
  exit $(( gradle_status != 0 ? gradle_status : 1 ))
fi

# Recorded repo-relative so the committed summary does not carry local paths.
commands=(
  "bash scripts/coverage/android.sh"
  "cd android && ./gradlew testDebugUnitTest koverXmlReportDebug koverHtmlReportDebug"
)
contracts_status="skipped: contracts/scripts/validate.mjs not found"
if [ -f "$VALIDATOR" ]; then
  commands+=("node contracts/scripts/validate.mjs --out android")
  if node "$VALIDATOR" --out android; then
    contracts_status="passed"
  else
    contracts_status="failed"
  fi
fi

summary_args=(
  --xml "$XML" --root "$ROOT" --out "$SUMMARY" --results "$RESULTS"
  --tests-exit "$gradle_status" --contracts "$contracts_status"
)
commands+=("node scripts/coverage/android-summary.mjs")
for c in "${commands[@]}"; do summary_args+=(--command "$c"); done
if [ "${COVERAGE_ENFORCE:-0}" = "1" ]; then summary_args+=(--enforce); fi

node "$ROOT/scripts/coverage/android-summary.mjs" "${summary_args[@]}"
summary_status=$?

if [ "$contracts_status" = "failed" ]; then
  echo "android.sh: contract output FAILED validation (node contracts/scripts/validate.mjs --out android)." >&2
  exit 1
fi
exit "$summary_status"
