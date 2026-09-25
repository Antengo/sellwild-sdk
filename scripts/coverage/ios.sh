#!/usr/bin/env bash
# iOS SDK coverage: runs the SellwildSDK XCTest suite on an iOS Simulator with
# code coverage, validates the contract payloads the tests emitted (when the
# contracts validator exists), checks that no real network request was blocked
# after the last test's check, and writes coverage-summary/ios.json (A10).
#
# Usage: bash scripts/coverage/ios.sh
#   SELLWILD_IOS_SIM_ID=<udid>       simulator to test on (default: a booted
#                                    iPhone, else an iPhone on the newest iOS runtime)
#   SELLWILD_IOS_DERIVED_DATA=<dir>  derived data (default: .coverage-tmp/ios-dd)
#   SELLWILD_CONTRACT_OUT=<dir>      contract output root; tests write <dir>/ios
#   COVERAGE_ENFORCE=1               also fail when the gate is under 95%
#
# Exit status: the xcodebuild status if tests failed (no summary is written),
# else 1 if contract validation failed or NetworkBlocker reported leftover
# requests, else the summary's status (non-zero only on a summary error, or on
# a missed gate with COVERAGE_ENFORCE=1).
#
# `swift test` cannot run this suite: UIKit, GMA and Prebid are iOS-only. Swift
# has no coverage-ignore pragma, so exclusions live in ios-summary.mjs.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Suite timing: .timings/suites.jsonl (tools/timings-report.mjs summarizes it).
source "$ROOT/tools/timing.sh"; timing_begin ios.sh
TMP="$ROOT/.coverage-tmp"
RESULT="$TMP/ios.xcresult"
DERIVED="${SELLWILD_IOS_DERIVED_DATA:-$TMP/ios-dd}"
LOG="$TMP/ios-test.log"
RESULTS_JSON="$TMP/ios-test-results.json"
XCCOV_JSON="$TMP/ios-xccov.json"
ARCHIVE_JSON="$TMP/ios-xccov-archive.json"
LLVM_JSON="$TMP/ios-llvm-cov.json"
# NetworkBlocker writes requests blocked after the last test's check here.
LEFTOVERS="$TMP/ios-network-leftovers.txt"
SUMMARY="$ROOT/coverage-summary/ios.json"
VALIDATOR="$ROOT/contracts/scripts/validate.mjs"
CONTRACT_OUT="${SELLWILD_CONTRACT_OUT:-$ROOT/contracts/out}/ios"
SOURCES="$ROOT/ios/Sources/SellwildSDK"
# SwiftPM links the SellwildSDK target statically into each test bundle.
TEST_BIN="$DERIVED/Build/Products/Debug-iphonesimulator/SellwildSDKTests.xctest/SellwildSDKTests"

# Repo-relative form of a path, so the committed summary carries no local paths.
rel() { case "$1" in "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;; *) printf '%s' "$1" ;; esac; }

# A booted iPhone first (reusing it skips a boot), else the first iPhone by
# name on the newest iOS runtime. Prints "<udid><TAB><label>".
pick_simulator() {
  xcrun simctl list devices available -j | node -e '
    let raw = "";
    process.stdin.on("data", (chunk) => (raw += chunk)).on("end", () => {
      const version = (runtime) => {
        const m = /\.iOS-(\d+)-(\d+)(?:-(\d+))?$/.exec(runtime);
        return m ? [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)] : null;
      };
      const phones = Object.entries(JSON.parse(raw).devices).flatMap(([runtime, list]) => {
        const v = version(runtime);
        if (!v) return [];
        return list.filter((d) => d.isAvailable !== false && d.name.startsWith("iPhone")).map((d) => ({ ...d, v }));
      });
      const order = (a, b) => b.v[0] - a.v[0] || b.v[1] - a.v[1] || b.v[2] - a.v[2] || a.name.localeCompare(b.name);
      const pick = phones.filter((d) => d.state === "Booted").sort(order)[0] ?? phones.sort(order)[0];
      if (!pick) process.exit(1);
      process.stdout.write(`${pick.udid}\t${pick.name}, iOS ${pick.v.slice(0, 2).join(".")}, ${pick.state}`);
    });'
}

if [ -n "${SELLWILD_IOS_SIM_ID:-}" ]; then
  SIM_ID="$SELLWILD_IOS_SIM_ID"
  SIM_LABEL="from SELLWILD_IOS_SIM_ID"
elif picked="$(pick_simulator)"; then
  SIM_ID="${picked%%$'\t'*}"
  SIM_LABEL="${picked#*$'\t'}"
else
  echo "ios.sh: no available iPhone simulator (see xcrun simctl list devices available)." >&2
  exit 1
fi
echo "ios.sh: testing on $SIM_ID ($SIM_LABEL)"

mkdir -p "$TMP"
# Stale output would be counted as this run's: xcodebuild refuses to reuse a
# result bundle, old .profraw files merge into the new profile, old emitted
# payloads would be validated again, and old leftovers would fail this run.
rm -rf "$RESULT" "$DERIVED/Build/ProfileData" "$CONTRACT_OUT" "$LEFTOVERS"

# Tests run inside the simulator, which passes a host variable to the test
# process only with the TEST_RUNNER_ prefix.
if [ -n "${SELLWILD_CONTRACT_OUT:-}" ]; then
  export TEST_RUNNER_SELLWILD_CONTRACT_OUT="$SELLWILD_CONTRACT_OUT"
fi
export TEST_RUNNER_SELLWILD_NETWORK_LEFTOVERS="$LEFTOVERS"

# Prints what NetworkBlocker reported after the last test, if anything.
report_leftovers() {
  [ -s "$LEFTOVERS" ] || return 1
  echo "ios.sh: NetworkBlocker stopped real network requests after the last test's check ($(rel "$LEFTOVERS")):" >&2
  cat "$LEFTOVERS" >&2
}

timing_phase simulator
cd "$ROOT" || exit 1

test_cmd=(command xcodebuild test -scheme SellwildSDK
  -destination "platform=iOS Simulator,id=$SIM_ID"
  -enableCodeCoverage YES -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT")
echo "ios.sh: building and testing (log: $(rel "$LOG"))"
"${test_cmd[@]}" >"$LOG" 2>&1
test_status=$?
timing_phase xcodebuild-build-test

if [ -d "$RESULT" ] && xcrun xcresulttool get test-results summary --path "$RESULT" >"$RESULTS_JSON" 2>>"$LOG"; then
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    console.log(`ios tests: ${r.result}: ${r.passedTests} passed, ${r.failedTests} failed, ${r.skippedTests} skipped, ${r.expectedFailures} expected failures`);
    for (const f of r.testFailures ?? []) console.log(`  FAILED ${f.testIdentifierString ?? f.testName}: ${f.failureText}`);
  ' "$RESULTS_JSON"
else
  rm -f "$RESULTS_JSON"
  echo "ios.sh: no test results in $(rel "$RESULT")." >&2
fi

if [ "$test_status" -ne 0 ]; then
  echo "ios.sh: tests FAILED (xcodebuild exit $test_status). Summary not written. Last errors from $(rel "$LOG"):" >&2
  grep -E 'error:|\*\* (TEST|BUILD) FAILED' "$LOG" | tail -30 >&2
  report_leftovers
  exit "$test_status"
fi

network_status="none"
if report_leftovers; then
  network_status="failed: $(grep -c . "$LEFTOVERS") report(s) in $(rel "$LEFTOVERS")"
fi

PROFDATA="$DERIVED/Build/ProfileData/$SIM_ID/Coverage.profdata"
if [ ! -f "$PROFDATA" ]; then
  PROFDATA="$(find "$DERIVED/Build/ProfileData" -name Coverage.profdata -print -quit 2>/dev/null)"
fi
if [ -z "$PROFDATA" ] || [ ! -f "$TEST_BIN" ]; then
  echo "ios.sh: coverage data missing (profile: ${PROFDATA:-none}, test binary: $(rel "$TEST_BIN"))." >&2
  exit 1
fi

xcrun xccov view --report --json "$RESULT" >"$XCCOV_JSON" || exit 1
xcrun xccov view --archive --json "$RESULT" >"$ARCHIVE_JSON" || exit 1
# Full export (not -summary-only): ios-summary.mjs counts regions and functions
# from the function records so it can leave out the A10 range comments.
xcrun llvm-cov export -instr-profile "$PROFDATA" "$TEST_BIN" -sources "$SOURCES" >"$LLVM_JSON" || exit 1

timing_phase coverage-export
commands=(
  "bash scripts/coverage/ios.sh"
  "command xcodebuild test -scheme SellwildSDK -destination 'platform=iOS Simulator,id=$SIM_ID' -enableCodeCoverage YES -derivedDataPath $(rel "$DERIVED") -resultBundlePath $(rel "$RESULT")"
  "xcrun xccov view --report --json $(rel "$RESULT")"
  "xcrun xccov view --archive --json $(rel "$RESULT")"
  "xcrun llvm-cov export -instr-profile $(rel "$PROFDATA") $(rel "$TEST_BIN") -sources $(rel "$SOURCES")"
)

contracts_status="skipped: contracts/scripts/validate.mjs not found"
if [ -f "$VALIDATOR" ]; then
  commands+=("node contracts/scripts/validate.mjs --out ios")
  if node "$VALIDATOR" --out ios; then
    contracts_status="passed"
  else
    contracts_status="failed"
  fi
fi

summary_args=(
  --xccov "$XCCOV_JSON" --archive "$ARCHIVE_JSON" --llvm "$LLVM_JSON" --results "$RESULTS_JSON"
  --root "$ROOT" --out "$SUMMARY" --tests-exit "$test_status" --contracts "$contracts_status"
  --network "$network_status"
)
timing_phase validate
commands+=("node scripts/coverage/ios-summary.mjs")
for c in "${commands[@]}"; do summary_args+=(--command "$c"); done
if [ "${COVERAGE_ENFORCE:-0}" = "1" ]; then summary_args+=(--enforce); fi

node "$ROOT/scripts/coverage/ios-summary.mjs" "${summary_args[@]}"
summary_status=$?

status="$summary_status"
if [ "$contracts_status" = "failed" ]; then
  echo "ios.sh: contract output FAILED validation (node contracts/scripts/validate.mjs --out ios)." >&2
  status=1
fi
if [ "$network_status" != "none" ]; then
  echo "ios.sh: FAILED: NetworkBlocker leftovers ($network_status)." >&2
  status=1
fi
timing_phase summary
exit "$status"
