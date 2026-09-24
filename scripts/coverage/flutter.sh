#!/usr/bin/env bash
# Flutter SDK coverage: runs flutter_test with line and branch coverage,
# validates the contract payloads the tests emitted (when the contracts
# validator exists), and writes coverage-summary/flutter.json (A10).
#
# Usage: bash scripts/coverage/flutter.sh
#   FLUTTER=/path/to/flutter   flutter binary (default: flutter on PATH)
#   COVERAGE_ENFORCE=1         also fail when the gate is under 95%
#   SELLWILD_CONTRACT_OUT=dir  contract output root; tests write dir/flutter
#                              (factory output) and dir/flutter-harness (the
#                              support self-test's round-trip)
#
# Contract checks: `validate.mjs --out flutter-harness` always runs.
# `validate.mjs --out flutter` runs once any test outside test/support calls
# emitContract, or anything was emitted there; from then on its "no emitted
# files" check applies. Before that the summary records it as skipped.
#
# Exit status: the flutter test status if tests failed, else 1 if contract
# validation failed, else the summary's status (non-zero only on a summary
# error, or on a missed gate with COVERAGE_ENFORCE=1). When no summary can be
# written, coverage-summary/flutter.json is removed rather than left stale.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="$ROOT/flutter"
LCOV="$PKG/coverage/lcov.info"
SUMMARY="$ROOT/coverage-summary/flutter.json"
VALIDATOR="$ROOT/contracts/scripts/validate.mjs"

# A summary from an earlier run must not survive a run that cannot write one.
rm -f "$SUMMARY"

# The emitter (test/support/contract_emitter.dart) and validate.mjs both write
# and read $SELLWILD_CONTRACT_OUT/flutter when it is set. Made absolute here,
# against the caller's directory, so both see the same directory after the cd
# below and nothing emitted skips validation.
if [ -n "${SELLWILD_CONTRACT_OUT:-}" ]; then
  mkdir -p "$SELLWILD_CONTRACT_OUT" || exit 1
  SELLWILD_CONTRACT_OUT="$(cd "$SELLWILD_CONTRACT_OUT" && pwd)" || exit 1
  export SELLWILD_CONTRACT_OUT
fi
CONTRACT_OUT="${SELLWILD_CONTRACT_OUT:-$ROOT/contracts/out}/flutter"
HARNESS_OUT="${SELLWILD_CONTRACT_OUT:-$ROOT/contracts/out}/flutter-harness"

FLUTTER="${FLUTTER:-$(command -v flutter || true)}"
if [ -z "$FLUTTER" ]; then
  echo "flutter.sh: flutter not found. Put it on PATH or set FLUTTER=/path/to/flutter." >&2
  exit 127
fi

cd "$PKG" || exit 1

# Stale output would be counted as this run's: old lcov inflates coverage, old
# emitted payloads get validated again. Only top-level .json files go: the
# emitters write nothing else, and SELLWILD_CONTRACT_OUT may point anywhere.
rm -f "$LCOV" "$CONTRACT_OUT"/*.json "$HARNESS_OUT"/*.json

test_cmd=("$FLUTTER" test --coverage --branch-coverage)
"${test_cmd[@]}"
test_status=$?

if [ ! -s "$LCOV" ]; then
  echo "flutter.sh: $LCOV was not written (flutter test exit $test_status)." >&2
  exit $(( test_status != 0 ? test_status : 1 ))
fi

# Recorded repo-relative so the committed summary does not carry local paths.
commands=("cd flutter && flutter test --coverage --branch-coverage")
contracts_status="skipped: contracts/scripts/validate.mjs not found"
harness_status="$contracts_status"
if [ -f "$VALIDATOR" ]; then
  commands+=("node contracts/scripts/validate.mjs --out flutter-harness")
  if node "$VALIDATOR" --out flutter-harness; then
    harness_status="passed"
  else
    harness_status="failed"
  fi

  emitters="$(grep -rl --include='*.dart' --exclude-dir=support 'emitContract(' "$PKG/test")"
  emitted="$(find "$CONTRACT_OUT" -maxdepth 1 -name '*.json' 2>/dev/null)"
  if [ -n "$emitters" ] || [ -n "$emitted" ]; then
    commands+=("node contracts/scripts/validate.mjs --out flutter")
    if node "$VALIDATOR" --out flutter; then
      contracts_status="passed"
    else
      contracts_status="failed"
    fi
  else
    contracts_status="skipped: no test outside test/support calls emitContract yet"
  fi
fi

summary_args=(
  --lcov "$LCOV" --pkg "$PKG" --out "$SUMMARY"
  --tests-exit "$test_status" --contracts "$contracts_status"
  --contracts-harness "$harness_status"
)
commands+=("node scripts/coverage/flutter-summary.mjs")
for c in "${commands[@]}"; do summary_args+=(--command "$c"); done
if [ "${COVERAGE_ENFORCE:-0}" = "1" ]; then summary_args+=(--enforce); fi

node "$ROOT/scripts/coverage/flutter-summary.mjs" "${summary_args[@]}"
summary_status=$?

if [ "$test_status" -ne 0 ]; then exit "$test_status"; fi
if [ "$contracts_status" = "failed" ] || [ "$harness_status" = "failed" ]; then
  exit 1
fi
exit "$summary_status"
