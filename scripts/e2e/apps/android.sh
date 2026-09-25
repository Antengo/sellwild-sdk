# App "android": the native Android sample, samples/feed-demo-android (Compose,
# application id com.sellwild.sample). It builds against the SDK in android/,
# published to mavenLocal first. Flows: e2e/maestro/android. Sourced by
# scripts/e2e/run.sh.

E2E_APP_ID=com.sellwild.sample
E2E_FLOWS="$ROOT/e2e/maestro/android"
ANDROID_SAMPLE="$ROOT/samples/feed-demo-android"

# Gradle with two workers (the machine rules), from both builds' own caches.
android_gradle() {
  local dir="$1"
  shift
  GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.workers.max=2" \
    "$dir/gradlew" -p "$dir" --console=plain --max-workers=2 "$@"
}

e2e_build() {
  E2E_APP_PATH="$ANDROID_SAMPLE/app/build/outputs/apk/debug/app-debug.apk"
  [ "${SELLWILD_E2E_NO_BUILD:-}" = "1" ] && return 0
  export ANDROID_HOME="$ANDROID_SDK_DIR"
  local status=0
  # 1. The SDK as checked out, to mavenLocal (com.sellwild:sdk:<its version>).
  # 2. The sample, against it. 3. Stop Gradle before the emulator boots: both
  # builds use one Gradle version, so one --stop ends every daemon.
  android_gradle "$ROOT/android" publishReleasePublicationToMavenLocal || status=1
  if [ "$status" -eq 0 ]; then
    android_gradle "$ANDROID_SAMPLE" :app:assembleDebug || status=1
  fi
  "$ROOT/android/gradlew" -p "$ROOT/android" --stop
  return "$status"
}

e2e_boot() {
  android_avd_pick || return 1
  android_emu_boot "$ANDROID_AVD" "$ART/emulator.log" || return 1
  E2E_DEVICE="$ANDROID_SERIAL_E2E"
}

e2e_install() {
  android_install "$E2E_DEVICE" "$E2E_APP_ID" "$E2E_APP_PATH"
}

e2e_shutdown() {
  android_emu_shutdown
  "$ROOT/android/gradlew" -p "$ROOT/android" --stop >/dev/null 2>&1 || true
}
