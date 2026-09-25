# logFailure: a practical guide

The short version of `FAILURES.md`. When the two differ, `FAILURES.md` wins.

## 1. What it is for

1. logFailure reports one SDK failure as a `clientFailure` event.
2. The event rides the SDK's existing events queue. No new endpoint.
3. It never throws, never blocks and never sends PII (FAILURES.md 3.4, 7.6).

The house rule (FAILURES.md sections 1 and 2):

1. Every failure path is a try/catch (or the failure branch of a Result) that calls logFailure with a registry code.
2. Never handle a failure by printing it. No `console.*`, `print`, `NSLog`, `Log.*`, `println`.
3. No empty catch blocks. No silent swallows.
4. Only two files per platform may print: the logFailure shell (its debug echo) and the debug logger.
5. Log once, at the lowest layer that sees the failure (FAILURES.md 9). Ad no-fill is not a failure (4.3).

## 2. How to call it

The parameters are the same everywhere: `code`, `component`, `severity`, `error`, `message`, `httpStatus`, `url`, `zoneId`. Only `code` and `component` are required. Severity defaults to `error`.

1. `severity`: `fatal` (the surface could not render), `error` (a fallback was used), `warn` (degraded but handled).
2. `error`: the caught error. Its name, message and (TS, Android) first stack frames are sent, sanitized.
3. `message`: short text. Never listing text, keywords or other user data.
4. `url`: only the host is sent.

### Core (TS)

`core/src/api.ts:85`:

```ts
import { logFailure } from './failures'

logFailure({ code: 'listings.fetch.http', component: 'listings', message: `HTTP ${res.status}`, httpStatus: res.status, url })
```

Pass the caught error as `error` (`core/src/api.ts:79`):

```ts
logFailure({ code: 'listings.fetch.network', component: 'listings', error, url })
```

### React Native (JS)

Import from `./failures`, not from core. That module sets client `react-native` (`react-native/src/failures.ts`). `react-native/src/SellwildBanner.tsx:103`:

```ts
import { logFailure } from './failures'

logFailure({
  code: 'ad.size.invalid',
  component: 'banner',
  severity: 'warn',
  message: `size ${String(size)} is not an AdSize`,
  zoneId: String(zoneId),
})
```

React Native JS reports only what fails in JS. The native SDKs report their own failures. The bridges call `SellwildFailures.setWrapper("react-native")`, so those events carry `wrapper` (`react-native/ios/SellwildRNModule.swift:76`, `react-native/android/src/main/java/com/sellwild/rnsdk/SellwildSdkPackage.kt:17`).

### iOS (Swift)

`ios/Sources/SellwildSDK/SellwildRemoteConfig.swift:184`:

```swift
SellwildFailures.log(code: .configFetchTimeout, component: .remoteConfig, error: error, url: url)
```

`code` is a `SellwildFailureCode`. `component` is a `SellwildFailureComponent`. `severity` is a `SellwildFailureSeverity` (`.fatal`, `.error`, `.warn`). `httpStatus` is `Int?`, `zoneId` is `String?`.

### Android (Kotlin)

`android/src/main/kotlin/com/sellwild/sdk/SellwildNativeAdView.kt:196`:

```kotlin
SellwildFailures.log(
    code = SellwildFailureCode.AD_NATIVE_CREATE_INVALID,
    component = SellwildFailureComponent.NATIVE,
    severity = SellwildFailureSeverity.ERROR,
    message = if (cacheId == null) "native win without a cache id" else "native ad could not be created from the cache",
    zoneId = zoneId,
)
```

All three are `String` constants in `failures/SellwildFailureCode.kt`. Pass the caught `Throwable` as `error = e`.

## 3. Add a new failure code

1. Pick `<area>.<operation>.<reason>` from the lists in FAILURES.md 4.1. Reuse a code when the meaning is the same.
2. Run add-code. It is the only way to change the registry (FAILURES.md 4.4):

   ```sh
   node contracts/scripts/add-code.mjs --code <area>.<operation>.<reason> --component listings \
     --severity error --clients core,react-native,ios,android \
     --description "One sentence." --note "Why the code exists."
   ```

3. It checks the entry, writes `failure-codes.json` and the `added` record in `failure-codes.sources.json`, then runs `scripts/gen-codes.mjs` to regenerate the three mirrors:
   1. `core/src/failures/codes.ts` (core and React Native)
   2. `ios/Sources/SellwildSDK/Failures/SellwildFailureCode.swift`
   3. `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailureCode.kt`
4. Never edit the registry or a mirror by hand.
5. Let another platform emit an existing code: `add-code.mjs --merge-clients --code <code> --clients <platform>`. Change a field: `--replace` with the whole entry.
6. The tests that check it:
   1. `node contracts/scripts/gen-codes.mjs --check` and `contracts/test/gen-codes.test.mjs`: each mirror equals what the registry generates.
   2. `contracts/test/registry.test.mjs` and `contracts/test/add-code.test.mjs`.
   3. Parity per platform: `core/test/failures-registry.test.ts`, `ios/Tests/SellwildSDKTests/Failures/SellwildFailureCodeTests.swift`, `android/src/test/kotlin/com/sellwild/sdk/failures/FailureCodesParityTest.kt`.
7. Then tell the widget. It vendors the registry and needs `node contracts/scripts/sync-check.mjs --update` in sellwild-widget.

## 4. What one event carries

FAILURES.md 6. One element of the events array:

```json
{
  "event": "clientFailure",
  "action": "listings.fetch.http",
  "label": "listings",
  "attributes": {
    "code": "weatherbug", "client": "ios", "clientVersion": "1.7.7", "severity": "error", "fv": "1",
    "msg": "HTTP 503", "httpStatus": "503", "host": "cache.sellwild.com", "zoneId": "43", "seq": "1", "repeat": "1"
  },
  "uid": "8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11",
  "createdTime": 1790000000000
}
```

1. `action` is the failure code. `label` is the component.
2. `attributes.code` is the partner code, not the failure code.
3. Every attribute value is a string. The allowlist is 16 keys (FAILURES.md 6.3). Empty optional ones are left out.
4. The URL is never sent, only `host`. Emails, UUIDs, IPs and long digit runs in `msg` are masked (FAILURES.md 7).
5. An event over 2048 bytes loses `stack`, then gets a shorter `msg` (FAILURES.md 6.4).

The limits (FAILURES.md 5):

1. Kill switches first: `EVENTS_ENABLED` off or `FAILURES_ENABLED` off drops the failure, `fatal` too.
2. Sampling: `FAILURES_SAMPLE_RATE` samples whole sessions by uid. `fatal` is never sampled out.
3. Per-session cap: 20 events. The 20th carries `capped: "1"`.
4. Dedupe: the same code, component, error name and message within 60 s is folded into the next event's `repeat`. One key sends at most 3 times.
5. The first event of a session, and every `fatal`, is flushed at once. The rest ride normal batching.

## 5. See events locally

### The debug echo

With debug on, each call prints one line, whether it was sent or dropped:

```
[Sellwild] failure <action> <label> <severity> <reason or "sent"> <msg>
```

1. Core and React Native JS: `await configure(partner, slug, { overrides: { debug: true } })`. It prints with `console.log` (`core/src/failures/index.ts:294`). `setDebugLogging(true)` from `@sellwild/sdk-core`, called before configure, also shows configure's own fetch failure.
2. iOS: `await SellwildSDK.configure(partnerCode: p, slug: s) { $0.debug = true }`, or remote `DEBUG: true`. It prints to the Xcode console. `SellwildFailures.setContext { $0.debug = true }` before configure also shows configure's own fetch failure.
3. Android: `SellwildSDK.configure(partnerCode, slug) { it.copy(debug = true) }`, or remote `DEBUG: true`. It goes to Logcat, tag `Sellwild`, level debug (`failures/SellwildLog.kt`): `adb logcat -s Sellwild`. `SellwildFailures.setContext { it.copy(debug = true) }` before configure also shows configure's own fetch failure.
4. The three e2e sample apps set `debug` to true.

### The sample apps' Diagnostics tab

See `e2e/README.md`.

1. Every sample uses partner `sellwild`, slug `sellwild-sample`. That slug has no CDN config, so each launch reports `config.fetch.http`. That is expected.
2. React Native sample (`samples/demo-app`): Diagnostics lists the failure codes sent this launch. It installs a sink with `setFailureContext({ sink })` (`samples/demo-app/src/sampleModel.ts:143`). The sink sees what JS and core report, not the native SDKs.
3. iOS and Android samples have no public failure sink. Diagnostics shows `SellwildFailures.context` instead.

### The e2e flows

1. `bash scripts/e2e/run.sh ios` (or `android`, `rn-ios`, `rn-android`). `--list` names them.
2. `e2e/maestro/common/diagnostics.yaml` checks the Diagnostics tab. With `FAILURE_SINK` on (React Native), it must show `config.fetch.http`.
3. `bash scripts/gate.sh --e2e` runs every app, one at a time.

## 6. Kill switches and CMS keys

FAILURES.md 10. All three are declared in `contracts/schemas/app-config.schema.json`.

1. `EVENTS_ENABLED`: the master switch. Off drops every event, clientFailure included.
2. `FAILURES_ENABLED`: off drops only clientFailure. Unset is on.
3. `FAILURES_SAMPLE_RATE`: 0 to 1. Unset or unreadable is 1.
4. Values are coerced the same way on every platform: `false`, `0`, `no`, `off` are off (FAILURES.md 5.3, 5.4).
5. Before the remote config loads, all three are unset, so configure's own failures still go out.
6. A local override wins over the remote `FAILURES_ENABLED`: core `overrides: { failuresEnabled: false }`, iOS and Android `failuresEnabledOverride` in `SellwildFailures.setContext`.

## 7. Where events go

1. POST to `https://events.sellwild.com/events/queue` (`core/src/config.ts:9`, `ios/Sources/SellwildSDK/SellwildAPI.swift:192`, `android/src/main/kotlin/com/sellwild/sdk/SellwildAPI.kt:539`).
2. From there the events pipeline (Lambda, then SQS, then BigQuery) loads them. It is owned outside these repos.
3. Open items: the BigQuery table name, and whether clientFailure gets a separate failures table.
4. Transport failures are never reported, so a dead events endpoint sends nothing about itself (FAILURES.md 8.4).

## 8. Where to read more

1. `contracts/FAILURES.md`: the full contract.
2. `contracts/failure-codes.json`: every code, its component, severity and clients.
3. `contracts/schemas/client-failure-event.schema.json`: the event, and its wire form.
4. `contracts/golden/`: the vectors every pure core must reproduce.
5. `TESTING.md`: the gate (`scripts/gate.sh`).
6. `COVERAGE.md`: coverage per platform and the exclusions.
7. `e2e/README.md`: the sample apps and their Maestro flows.
