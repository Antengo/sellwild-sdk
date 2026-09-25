# App "flutter-android": the Flutter sample, samples/flutter-demo, on the
# Android emulator (application id com.sellwild.sample.flutter). It depends on
# the SDK in flutter/ by path. Flows: e2e/maestro/flutter (shared with
# flutter-ios). Sourced by scripts/e2e/run.sh.

E2E_APP_ID=com.sellwild.sample.flutter
E2E_FLOWS="$ROOT/e2e/maestro/flutter"

e2e_build() {
  E2E_APP_PATH="$FLUTTER_SAMPLE/build/app/outputs/flutter-apk/app-debug.apk"
  [ "${SELLWILD_E2E_NO_BUILD:-}" = "1" ] && return 0
  export ANDROID_HOME="$ANDROID_SDK_DIR"
  local status=0
  # A debug APK for the emulator's ABI only (arm64), with two Gradle workers
  # (the machine rules). Then stop Gradle before the emulator boots.
  flutter_sample pub get || status=1
  if [ "$status" -eq 0 ]; then
    GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.workers.max=2" \
      flutter_sample build apk --debug --target-platform android-arm64 || status=1
  fi
  flutter_gradle_stop
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
  flutter_gradle_stop >/dev/null 2>&1 || true
}
