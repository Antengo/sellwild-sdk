#!/usr/bin/env bash
# Compiles the React Native bridge's Android code (react-native/android, the
# Gradle project :sellwild-react-native-sdk) inside the React Native sample,
# samples/demo-app, against the Android SDK in android/ as checked out.
#
#   bash scripts/rn/compile-bridge-android.sh
#
# Steps: npm ci in samples/demo-app when its node_modules is stale (Gradle
# reads React Native's Gradle plugin from there), publish android/ to
# mavenLocal, compile the bridge's Kotlin, stop Gradle. It builds no app.
#
# It takes no lock itself. On the agents' machine run it through the native
# lock, or run the gate that calls it through the lock (one native build at
# a time). Needs a JDK 17 (found when JAVA_HOME is not one) and the Android
# SDK (ANDROID_HOME, default ~/Library/Android/sdk).
#
# Exit status: 0 when the bridge compiles, 1 otherwise.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../e2e/lib/rn.sh
source "$ROOT/scripts/e2e/lib/rn.sh"

export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
start=$(date +%s)
status=0
rn_java17 || exit 1
rn_npm_ci_if_stale "$RN_SAMPLE" || status=1
[ "$status" -eq 0 ] && { rn_sdk_publish || status=1; }
if [ "$status" -eq 0 ]; then
  rn_gradle_in "$RN_ANDROID" :sellwild-react-native-sdk:compileDebugKotlin || status=1
fi
rn_gradle_stop >/dev/null 2>&1
if [ "$status" -eq 0 ]; then
  echo "rn-bridge-android: the bridge compiled ($(( $(date +%s) - start ))s)"
else
  echo "rn-bridge-android: FAILED ($(( $(date +%s) - start ))s)" >&2
fi
exit "$status"
