# App "flutter-ios": the Flutter sample, samples/flutter-demo, on the iOS
# Simulator (bundle id com.sellwild.sample.flutter). It depends on the SDK in
# flutter/ by path. Flows: e2e/maestro/flutter (shared with flutter-android).
# Sourced by scripts/e2e/run.sh.

E2E_APP_ID=com.sellwild.sample.flutter
E2E_FLOWS="$ROOT/e2e/maestro/flutter"

e2e_build() {
  ios_sim_pick || return 1
  E2E_APP_PATH="$FLUTTER_SAMPLE/build/ios/iphonesimulator/Runner.app"
  [ "${SELLWILD_E2E_NO_BUILD:-}" = "1" ] && return 0
  # A debug build (the only kind a simulator runs). flutter keeps its own
  # caches in the sample's build/ and ios/ folders (gitignored).
  flutter_sample pub get && flutter_sample build ios --simulator --debug
}

e2e_boot() {
  ios_sim_boot "$IOS_SIM_ID" || return 1
  E2E_DEVICE="$IOS_SIM_ID"
}

e2e_install() {
  ios_sim_install "$E2E_DEVICE" "$E2E_APP_ID" "$E2E_APP_PATH"
}

e2e_shutdown() {
  ios_sim_shutdown
}
