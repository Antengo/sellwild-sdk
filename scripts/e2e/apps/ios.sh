# App "ios": the native iOS sample, samples/feed-demo-ios (xcodegen project
# SellwildSample.xcodeproj, scheme SellwildSample, SDK from the root
# Package.swift). Flows: e2e/maestro/ios. Sourced by scripts/e2e/run.sh.

E2E_APP_ID=com.sellwild.sample
E2E_FLOWS="$ROOT/e2e/maestro/ios"
IOS_PROJECT="$ROOT/samples/feed-demo-ios/SellwildSample.xcodeproj"
IOS_DERIVED="$E2E_CACHE/ios/DerivedData"

e2e_build() {
  ios_sim_pick || return 1
  E2E_APP_PATH="$IOS_DERIVED/Build/Products/Debug-iphonesimulator/SellwildSample.app"
  [ "${SELLWILD_E2E_NO_BUILD:-}" = "1" ] && return 0
  # Derived data and the SwiftPM checkouts stay in the cache between runs.
  xcodebuild -project "$IOS_PROJECT" -scheme SellwildSample -configuration Debug \
    -destination "platform=iOS Simulator,id=$IOS_SIM_ID" -derivedDataPath "$IOS_DERIVED" \
    COMPILER_INDEX_STORE_ENABLE=NO build
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
