# e2e ids

`ids.json` is the one list of stable element ids for the sample apps (named "Sellwild Sample" on every platform) and their Maestro flows in `e2e/maestro/`.

## Rules

1. Add an id here before you use it in an app or a flow.
2. Never rename or remove an id. Flows on other platforms use it.
3. Ids look like `sw.<screen>.<thing>`: lower case, dots between parts, `_` inside a part.
4. The app sets ids on its own containers:
   1. iOS: `accessibilityIdentifier`.
   2. Android views: resource id. Compose: `testTag` with `testTagsAsResourceId`. An SDK view sets its accessibility node's `viewIdResourceName`: a resource name cannot hold a dot.
   3. Flutter: `Semantics(identifier:)`.
   4. React Native: `testID`.
5. When a flow needs an id inside an SDK view (a listing row in the SDK feed), the SDK sets it. Add a unit test for it, and name the file under `sdk` in the entry.
6. `setBy` says who sets the id: `app`, `sdk` or both.
7. `text` gives the text a flow may assert, when the text is part of the contract.
8. `missingOn` names the platforms that do not have the element, and why. Flows for those platforms skip it.

## Checks

1. `contracts/test/e2e-ids.test.mjs` fails when a flow in `e2e/maestro/` or a sample app uses an `sw.*` id that is not listed here.
2. The iOS SDK test `testListingAndAdRowsCarryTheE2EIdentifiers` checks the SDK feed's ids are listed here.
3. The Android SDK test `SellwildFeedE2EIdTest` checks the same, on the resource-id UI Automator reads.
