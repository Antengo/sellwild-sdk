#!/usr/bin/env bash
# Compiles the React Native bridge's iOS code (react-native/ios, the pod
# SellwildSDK-RN) inside the React Native sample, samples/demo-app, against
# the iOS SDK in ios/ as checked out (the local pod SellwildSDK).
#
#   bash scripts/rn/compile-bridge-ios.sh
#
# Steps: npm ci in samples/demo-app when its node_modules is stale (the
# Podfile reads React Native from there), pod install when Pods/ does not
# match Podfile.lock, then xcodebuild of the SellwildSDK-RN pod target alone
# (with what it depends on: React-Core, SellwildSDK and their pods) for the
# simulator. It builds no app and boots no simulator. Derived data stays in
# e2e/.cache/rn-bridge-ios (gitignored).
#
# It runs inside the native lock (scripts/e2e/native-lock.sh, one native
# build or booted device at a time), pod install and xcodebuild both: it
# takes the lock unless it is inside it already (the gate run under it, or
# SELLWILD_E2E_LOCKED set by an outer holder). See scripts/e2e/lib/lock.sh.
#
# Exit status: 0 when the bridge compiles, 1 otherwise.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../e2e/lib/lock.sh
source "$ROOT/scripts/e2e/lib/lock.sh"
native_lock_reexec rn-bridge-ios "$ROOT/scripts/rn/compile-bridge-ios.sh" "$@"
# shellcheck source=../e2e/lib/rn.sh
source "$ROOT/scripts/e2e/lib/rn.sh"

DERIVED="${SELLWILD_E2E_CACHE:-$ROOT/e2e/.cache}/rn-bridge-ios/DerivedData"
start=$(date +%s)
status=0
rn_npm_ci_if_stale "$RN_SAMPLE" || status=1
[ "$status" -eq 0 ] && { rn_pod_install || status=1; }
if [ "$status" -eq 0 ]; then
  xcodebuild -workspace "$RN_IOS/SellwildDemo.xcworkspace" -scheme SellwildSDK-RN -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
    ONLY_ACTIVE_ARCH=YES ARCHS=arm64 COMPILER_INDEX_STORE_ENABLE=NO build -quiet || status=1
fi
if [ "$status" -eq 0 ]; then
  echo "rn-bridge-ios: the bridge compiled ($(( $(date +%s) - start ))s)"
else
  echo "rn-bridge-ios: FAILED ($(( $(date +%s) - start ))s)" >&2
fi
exit "$status"
