# React Native sample

The React Native sample app is `samples/demo-app` (app "Sellwild Sample", id `com.sellwild.sample.rn`).

1. It has what the old `App.tsx` here showed, on current API: `configure`, `SellwildBanner`, `useSellwildListings`, `SellwildListingCard`, and the deprecated `SellwildWidget` on its Legacy screen only.
2. It adds `SellwildFeed`, the native feed of listings with native ads between them. That is its first screen.
3. The old file was a copy-paste template with `YOUR_PARTNER_CODE`. The new app runs: Metro takes the SDK from `react-native/` and `core/` in this repo, and the native bridge comes in as local pods and a Gradle project. So it cannot drift from the API.
4. `bash scripts/e2e/run.sh rn-ios` and `bash scripts/e2e/run.sh rn-android` build it and run its Maestro flows. `e2e/README.md` has the details.
