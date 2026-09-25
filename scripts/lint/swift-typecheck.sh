#!/usr/bin/env bash
# Swift type check for the gate's --fast mode: compiles the SellwildSDK
# target and its test targets for the iOS Simulator, and runs nothing.
#
#   bash scripts/lint/swift-typecheck.sh
#   SELLWILD_IOS_SIM_ID=<udid>       simulator to build for (default: the one
#                                    scripts/coverage/ios.sh picks)
#   SELLWILD_IOS_DERIVED_DATA=<dir>  derived data (default: .coverage-tmp/ios-dd)
#
# It is `xcodebuild build-for-testing` with the same scheme, destination,
# coverage setting and derived data as scripts/coverage/ios.sh, so the two
# share one build: after either one, the other only rebuilds what changed.
# A plain `xcodebuild build` cannot take -enableCodeCoverage, and a build
# without it would recompile everything, twice per gate run.
#
# No simulator boots. Measured 2026-09-24 on an M1: 5-7s warm (nothing or one
# file changed), 28s cold (empty derived data).
#
# Exit status: xcodebuild's. On a failure the compiler errors are printed; the
# whole log is .coverage-tmp/swift-typecheck.log.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$ROOT/.coverage-tmp"
DERIVED="${SELLWILD_IOS_DERIVED_DATA:-$TMP/ios-dd}"
LOG="$TMP/swift-typecheck.log"

# The same pick as scripts/coverage/ios.sh: a booted iPhone first, else the
# first iPhone by name on the newest iOS runtime. Prints the UDID.
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
      process.stdout.write(pick.udid);
    });'
}

SIM_ID="${SELLWILD_IOS_SIM_ID:-}"
if [ -z "$SIM_ID" ] && ! SIM_ID="$(pick_simulator)"; then
  echo "swift-typecheck: no available iPhone simulator (see xcrun simctl list devices available)." >&2
  exit 1
fi

mkdir -p "$TMP"
cd "$ROOT" || exit 1
command xcodebuild build-for-testing -scheme SellwildSDK \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -enableCodeCoverage YES -derivedDataPath "$DERIVED" >"$LOG" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
  echo "swift-typecheck: FAILED (xcodebuild exit $status). Errors from ${LOG#"$ROOT"/}:" >&2
  grep -E '(^|: )error:|\*\* (TEST )?BUILD FAILED' "$LOG" | sort -u | tail -40 >&2
  exit "$status"
fi
echo "swift-typecheck: SellwildSDK and its tests compile (simulator $SIM_ID)"
