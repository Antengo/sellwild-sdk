# App "rn-android": the React Native sample, samples/demo-app, on the Android
# emulator (application id com.sellwild.sample.rn). A release build: the JS
# bundle is inside the APK, so no Metro server runs while the flows do. The
# SDK in android/ is published to mavenLocal first; Metro takes the JS SDK
# from react-native/ and core/. Flows: e2e/maestro/react-native (shared with
# rn-ios). Sourced by scripts/e2e/run.sh.

E2E_APP_ID=com.sellwild.sample.rn
E2E_FLOWS="$ROOT/e2e/maestro/react-native"

e2e_build() {
  E2E_APP_PATH="$RN_ANDROID/app/build/outputs/apk/release/app-release.apk"
  [ "${SELLWILD_E2E_NO_BUILD:-}" = "1" ] && return 0
  export ANDROID_HOME="$ANDROID_SDK_DIR"
  rn_java17 || return 1
  local status=0
  # 1. npm packages and core's dist. 2. The SDK, to mavenLocal. 3. The app:
  # assembleRelease runs Metro once to bundle the JS (Hermes bytecode), then
  # exits. Only the emulator's ABI. 4. Stop Gradle before the emulator boots.
  rn_js_deps || status=1
  [ "$status" -eq 0 ] && { rn_sdk_publish || status=1; }
  if [ "$status" -eq 0 ]; then
    rn_gradle_in "$RN_ANDROID" :app:assembleRelease -PreactNativeArchitectures=arm64-v8a || status=1
  fi
  rn_gradle_stop
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
  rn_gradle_stop >/dev/null 2>&1 || true
}
