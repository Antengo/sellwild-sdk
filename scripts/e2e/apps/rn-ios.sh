# App "rn-ios": the React Native sample, samples/demo-app, on the iOS
# Simulator (bundle id com.sellwild.sample.rn). A Release build: the JS bundle
# is inside the app, so no Metro server runs while the flows do. The SDK and
# the bridge come in as local pods (ios/Podfile); Metro takes the JS SDK from
# react-native/ and core/. Flows: e2e/maestro/react-native (shared with
# rn-android). Sourced by scripts/e2e/run.sh.

E2E_APP_ID=com.sellwild.sample.rn
E2E_FLOWS="$ROOT/e2e/maestro/react-native"
RN_IOS_DERIVED="$E2E_CACHE/rn-ios/DerivedData"

e2e_build() {
  ios_sim_pick || return 1
  E2E_APP_PATH="$RN_IOS_DERIVED/Build/Products/Release-iphonesimulator/SellwildDemo.app"
  [ "${SELLWILD_E2E_NO_BUILD:-}" = "1" ] && return 0
  # 1. npm packages and core's dist. 2. pod install when Pods/ is stale.
  # 3. The app: its "Bundle React Native code and images" phase runs Metro
  # once to bundle the JS (Hermes bytecode), then exits. Derived data stays in
  # the cache between runs; only the simulator's arch is built.
  rn_js_deps || return 1
  rn_pod_install || return 1
  xcodebuild -workspace "$RN_IOS/SellwildDemo.xcworkspace" -scheme SellwildDemo -configuration Release \
    -destination "platform=iOS Simulator,id=$IOS_SIM_ID" -derivedDataPath "$RN_IOS_DERIVED" \
    ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO build
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
