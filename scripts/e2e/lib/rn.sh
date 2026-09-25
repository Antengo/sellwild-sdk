# React Native helpers for scripts/e2e/apps/rn-*.sh (rn-ios, rn-android) and
# scripts/rn/*.sh (the bridge compile steps). Sourced; defines functions only.
# The caller sets ROOT (the sellwild-sdk checkout).
#
# The app is samples/demo-app (React Native 0.74, npm). Metro maps
# @sellwild/react-native-sdk to react-native/ and @sellwild/sdk-core to core/
# (metro.config.js), so the app runs the SDK as checked out. The bridge's
# native code comes in as local pods (ios/Podfile) and as the Gradle project
# :sellwild-react-native-sdk (android/settings.gradle).

RN_SAMPLE="$ROOT/samples/demo-app"
RN_IOS="$RN_SAMPLE/ios"
RN_ANDROID="$RN_SAMPLE/android"

# Sets JAVA_HOME to a JDK 17 when it is not one (Gradle 8.6 and RN 0.74 want 17).
rn_java17() {
  local candidate
  if [ -n "${JAVA_HOME:-}" ] && "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "17'; then
    return 0
  fi
  for candidate in "$(/usr/libexec/java_home -v 17 2>/dev/null || true)" /Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home; do
    if [ -n "$candidate" ] && "$candidate/bin/java" -version 2>&1 | grep -q 'version "17'; then
      export JAVA_HOME="$candidate"
      return 0
    fi
  done
  echo "rn: no JDK 17 (set JAVA_HOME)" >&2
  return 1
}

# npm ci in $1 when its node_modules is missing or older than its lockfile.
rn_npm_ci_if_stale() {
  local dir="$1"
  if [ -d "$dir/node_modules" ] && [ "$dir/node_modules/.package-lock.json" -nt "$dir/package-lock.json" ]; then
    return 0
  fi
  echo "rn: npm ci in ${dir#"$ROOT"/}"
  npm --prefix "$dir" ci --no-audit --no-fund
}

# The JavaScript side: the app's and core's packages, then core's dist.
# Metro reads @sellwild/sdk-core from core/package.json "main" (dist/index.js),
# which is gitignored, so it is built here every time (tsgo, under a second).
rn_js_deps() {
  rn_npm_ci_if_stale "$RN_SAMPLE" || return 1
  rn_npm_ci_if_stale "$ROOT/core" || return 1
  npm --prefix "$ROOT/core" run --silent build
}

# pod install in the app's ios/ when Pods/ does not match Podfile.lock, or
# when React Native's codegen output is missing. pod install writes that
# output into node_modules/react-native, so an npm ci deletes it, and the
# app build then fails in React-Fabric's "Check rncore" phase.
rn_pod_install() {
  local rncore="$RN_SAMPLE/node_modules/react-native/ReactCommon/react/renderer/components/rncore"
  if [ -f "$RN_IOS/Pods/Manifest.lock" ] && cmp -s "$RN_IOS/Podfile.lock" "$RN_IOS/Pods/Manifest.lock" && [ -d "$rncore" ]; then
    echo "rn: Pods match Podfile.lock"
    return 0
  fi
  [ -d "$rncore" ] || echo "rn: React Native codegen output is missing (after npm ci)"
  echo "rn: pod install"
  (cd "$RN_IOS" && RCT_NEW_ARCH_ENABLED=0 pod install)
}

# Gradle in $1 with two workers (the machine rules).
rn_gradle_in() {
  local dir="$1"
  shift
  GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.workers.max=2" \
    "$dir/gradlew" -p "$dir" --console=plain --max-workers=2 "$@"
}

# The Android SDK in android/, as checked out, to mavenLocal
# (com.sellwild:sdk:<its version>). The app and the bridge take it from there.
rn_sdk_publish() {
  rn_gradle_in "$ROOT/android" publishReleasePublicationToMavenLocal
}

# Every Gradle daemon these builds start: the SDK's and the app's use
# different Gradle versions, so each is stopped.
rn_gradle_stop() {
  "$ROOT/android/gradlew" -p "$ROOT/android" --stop
  [ -x "$RN_ANDROID/gradlew" ] && "$RN_ANDROID/gradlew" -p "$RN_ANDROID" --stop
  return 0
}
