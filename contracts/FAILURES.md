# clientFailure contract, fv 1

This is the formal failure-reporting contract for all six clients: core, react-native, ios, android, flutter and widget. It merges the phase-1 proposal and the orchestrator amendments A1–A10 into one document. Where they differed, the amendments won. Section 17 lists every decision this document adds on top of both.

The reference implementation is `reference/log-failure.mjs`. The golden vectors in `golden/` are generated from it. If this document and the reference disagree, fix the wrong one and regenerate the vectors in the same change (`npm run vectors`).

## 0. Files

| file | what it is |
|---|---|
| `FAILURES.md` | This contract. |
| `failure-codes.json` | Canonical code registry (section 4). |
| `failure-codes.sources.json` | Where each code came from: all 641 phase-1 failure points, each mapped to a code or excluded with a reason, plus `added` for later codes. |
| `scripts/add-code.mjs`, `scripts/gen-codes.mjs` | The only way to change the registry, and the generator of the four platform mirrors (section 4.4). |
| `reference/log-failure.mjs` | Dependency-free JS reference of the pure core (sections 5–7). |
| `golden/log-failure.vectors.json` | Golden vectors every platform must reproduce (section 12). |
| `golden/log-failure.utf16.vectors.json` | Extra vectors with lone UTF-16 surrogates, for TS, Kotlin and Dart only. |
| `schemas/client-failure-event.schema.json` | JSON Schema of the event (and of the queue-stamped wire form). |
| `schemas/failure-codes.schema.json` | JSON Schema of the registry. |
| `print-gate.allowlist.json`, `scripts/print-gate.mjs` | The print gate (section 11). |
| `expectations/drift/<platform>.json` | Known cross-platform drift, one file per SDK platform (section 14). |

## 1. The rule (A1)

1. Every failure path is a try/catch (Swift do/catch, Kotlin runCatching or try, Dart try/on, or the failure branch of a Result) that calls logFailure with a registry code.
2. A failure is never handled by printing:
   - TS: no `console.error/warn/log/info/debug/trace`.
   - Swift: no `print`, `debugPrint`, `dump`, `NSLog`, `os_log`.
   - Kotlin: no `Log.e/w/i/d/v/wtf`, `println`, `print`, `printStackTrace`, `System.out/err`.
   - Dart: no `print`, `debugPrint`.
3. No empty catch blocks. A catch body that holds only comments is empty.
4. No silent swallows (`.catch(() => {})`, `.catchError((_) => null)`, `try?` that throws away a real failure).

## 2. Where printing is allowed (A2)

Only two modules per platform may print:

1. The logFailure module's debug echo. It prints one line per failure call, and only when the SDK or widget debug flag is on.
2. One debug logger module. Every call is a no-op unless debug is on. It is for trace output that is not a failure.

All lanes use these exact paths:

| platform | pure core | shell (logFailure, context) | debug logger |
|---|---|---|---|
| core (TS) | `core/src/failures/core.ts` | `core/src/failures/index.ts` | `core/src/debug-log.ts` |
| react-native | uses core | `react-native/src/failures.ts` (thin: sets client `react-native`, re-exports) | uses core `debug-log` |
| widget | `src/failures/core.ts` | `src/failures/index.ts` | `src/failures/debugLog.ts` |
| iOS | `ios/Sources/SellwildSDK/Failures/SellwildFailuresCore.swift` | `ios/Sources/SellwildSDK/Failures/SellwildFailures.swift` | `ios/Sources/SellwildSDK/Failures/SellwildLog.swift` |
| Android | `android/src/main/kotlin/com/sellwild/sdk/failures/FailuresCore.kt` | `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt` | `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildLog.kt` |
| Flutter | `flutter/lib/src/failures/failures_core.dart` | `flutter/lib/src/failures/sellwild_failures.dart` | `flutter/lib/src/failures/sellwild_log.dart` |

The debug echo line is:

```
[Sellwild] failure <action> <label> <severity> <reason or "sent"> <msg>
```

`msg` is the sanitized message (section 7), never the raw input. `<msg>` and the space before it are left out when there is no message.

## 3. Public API (A3)

### 3.1 Names

1. TS (core and widget): `logFailure(input)`, `setFailureContext(partial)`, `resetFailuresForTests()`, `FailureCode` (string union from the registry), `FAILURE_CODES`.
2. Swift: `SellwildFailures.log(code:component:severity:error:message:httpStatus:url:zoneId:)`, `SellwildFailures.setContext(...)`, `SellwildFailures.setWrapper(_:)`, `SellwildFailures.resetForTests()`.
3. Kotlin: `SellwildFailures.log(...)` with named and default parameters, `SellwildFailures.setContext(...)`, `SellwildFailures.setWrapper(String)`, `SellwildFailures.resetForTests()`.
4. Dart: `SellwildFailures.log(code:, component:, ...)`, `SellwildFailures.setContext(...)`, `SellwildFailures.resetForTests()`.
5. React Native: JS calls core's logFailure with client `react-native`. The native bridge calls `setWrapper('react-native')` so native failures carry `wrapper`.

The parameters are the same everywhere: `code`, `component`, `severity?`, `error?`, `message?`, `httpStatus?`, `url?`, `zoneId?`. logFailure returns nothing (Dart too: `void`, not a `Future`).

### 3.2 Context

The context holds `partnerCode`, `client`, `clientVersion`, `debug`, `eventsEnabled`, `failuresEnabled`, `failuresSampleRate`, `wrapper`, `release` (widget only), and injectable dependencies: clock, uid provider and event sink.

1. `configure()` (or widget theme resolution) sets `partnerCode` FIRST, before any fetch, so config failures carry the partner.
2. `clientVersion` is `SDK_VERSION` on SDK clients and the package.json version on the widget (for example `1.1.114`).
3. `eventsEnabled` and `failuresEnabled` are the raw remote values of `EVENTS_ENABLED` and `FAILURES_ENABLED`. A local `failuresEnabled` override wins over the remote value. The pure core coerces them (section 5.3).
4. Before the remote config is loaded these values are unset. Unset means on and rate 1, so configure and remote-config failures are still reported.

### 3.3 From the call to the pure-core input

The shell turns the call into the pure-core input `{ code, component, severity, errName, errMessage, message, stack, httpStatus, url, zoneId }`:

1. `error` becomes `errName`, `errMessage` and, where stacks are sent, `stack`:
   - TS: an `Error` gives `name`, `message`, `stack`. A string gives `errMessage`. Anything else is ignored.
   - Swift: `errName` is the type name (`String(describing: type(of: error))`); for a bridged `NSError`, `"<domain>(<code>)"`. `errMessage` is `localizedDescription`. No stack (off on iOS).
   - Kotlin: `errName` is `javaClass.simpleName`, `errMessage` is `message`, `stack` is the first frames of `stackTrace`, one `Class.method(File.kt:line)` per line, no header line.
   - Dart: `errName` is `runtimeType.toString()`, `errMessage` is the exception's message (`toString()` when it has none). No stack.
2. `message`, `httpStatus`, `url` and `zoneId` pass through as given, after the input cap in item 4.
3. `stack` is sent by TS (core, widget) and Android only.
4. Input cap. Every shell cuts `message` and `errMessage` to their first 1000 UTF-16 code units, and `stack` to its first 2000, BEFORE the pure core. The sanitizer patterns (7.4, 7.5) backtrack superlinearly on long runs of `[A-Za-z0-9._%+-]` (10,000 characters take about 0.35 s in V8, more on Hermes, the JVM and ICU), and logFailure must never block (3.4). Only 200 code points of message and 5 frames are ever sent, so the cap changes only pathological input, and it changes it the same way everywhere:
   - A surrogate pair split by the cut leaves a lone high surrogate, which cleanText (7.1) turns into U+FFFD. Swift strings cannot hold one, so Swift drops the pair and appends U+FFFD itself. Every platform hands the core the same text.
   - Non-strings pass through unchanged.
   - TS: when `stack` is over 2000 units and starts with V8's header (`<name>: <message>`, or `<name>` alone when the message is empty) followed by a line break or the end, the header is removed before the cut. Otherwise a long message would push every frame out of the cut. Under the cap the pure core drops the header itself (7.4 step 2).
   - The reference is `capInput` and `INPUT_LIMITS` in `reference/log-failure.mjs`. The shells are core `core/src/failures/index.ts`, iOS `SellwildFailures.capInput`, Android `SellwildFailures.capInput`, Flutter `SellwildFailures._bounded`, and the widget's `src/failures/index.ts`.

### 3.4 The shell

```
logFailure(input):
  if reentrant: return                       // nested call from inside logFailure
  reentrant = true
  try:
    r = decideFailure(state, toCoreInput(input), context, uidProvider(), clock())
    state = r.state
    if context.debug: echo one line (section 2)
    if r.event: sink.push(r.event); if r.flushNow: sink.flushNow()
  catch anything: internalErrors += 1; echo it when debug is on   // never rethrow
  finally: reentrant = false
```

1. The body is wrapped: TS try/catch, Swift do/catch with no `try!` and no force unwrap, Kotlin runCatching, Dart try/catch plus `unawaited(future.catchError(...))`.
2. It never awaits the network and never blocks the main thread.
3. The reentrancy flag is thread-local or atomic on Swift and Kotlin.
4. The catch inside logFailure is the one place a failure is not reported, because reporting it would recurse. It is still not empty: it counts the error in an internal counter that tests can read (`resetForTests()` clears it) and echoes it when debug is on.

## 4. Codes

### 4.1 Format

1. `<area>.<operation>.<reason>`, at most 64 characters, matching the whole string:
   `^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`
2. Areas: `config`, `listings`, `localized`, `ad`, `house`, `feed`, `bridge`, `widget`, `video`, `growthcode`, `geo`, `storage`. `client` is reserved for `client.code.invalid`.
3. Reasons: `network`, `timeout`, `http`, `parse`, `invalid`, `missing`, `exception`, `unsupported`.
4. The pure core replaces any code that fails the format with `client.code.invalid` (section 5). It checks only the format, not membership in the registry.

### 4.2 Registry (A4)

1. `failure-codes.json` is canonical and language neutral. Each entry: `code`, `area`, `operation`, `reason`, `component` (usual label), `severity` (recommended), `clients` (platforms that emit it), `description`.
2. Each platform mirrors the codes whose `clients` include it as constants. `scripts/gen-codes.mjs` generates the four mirrors (`core/src/failures/codes.ts`, `ios/Sources/SellwildSDK/Failures/SellwildFailureCode.swift`, `android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailureCode.kt`, `flutter/lib/src/failures/sellwild_failure_code.dart`); nobody edits them by hand. A parity test on each platform reads the JSON and checks its constants match. The core mirror holds the codes for `core` and `react-native`, because react-native re-exports core.
3. The widget vendors the registry (sha256 sync check) and may add widget-only codes in `sellwild-widget/contracts/failure-codes.widget.json`, same format.
4. `severity` in the registry is a recommendation for call sites. logFailure itself defaults to `error` when no severity is passed.
5. Seeded from all 641 phase-1 failure points (219 codes). `failure-codes.sources.json` maps each point to its code, or to an exclusion: no-fill, events transport, kill switch, by design, log-once, node tooling, known drift, defect, in-page, caller abort, privacy, lifecycle, dead code, security review, unreachable. Codes added later are listed in its `added` array with the date and why.

### 4.3 Codes that are never logged

1. Ad no-fill and no-bid. The existing `adError` / `adNoBids` events cover them. Log a GAM or Prebid load failure only for a reason other than no-fill.
2. Anything the events transport does (section 8.4).
3. The kill switches themselves.

### 4.4 How to add a code

1. Pick the area, operation and reason from 4.1. Reuse an existing code when the meaning is the same; the call site passes its own component.
2. Run `node contracts/scripts/add-code.mjs` with the entry as JSON or as flags. area, operation and reason may be left out; they come from the code.

   ```
   node contracts/scripts/add-code.mjs --code widget.webview_load.http --component webview \
     --severity error --clients react-native,ios,android,widget \
     --description "The widget WebView got an HTTP error status (4xx or 5xx) for its page or a main-frame resource." \
     --note "Why the code exists."
   ```

   It checks the entry (format, area, reason, component and severity enums, clients, a one-sentence description with no `/*` or `*/`, which would break a generated doc comment; no no-fill, no-bid or events code, per 4.3), takes `contracts/.lock`, re-reads the registry, inserts the entry in code order, records the new code in `failure-codes.sources.json` `added`, writes both files, regenerates the four mirrors and releases the lock. Adding an identical entry again changes nothing.
3. Never edit `failure-codes.json` or a mirror by hand. `node contracts/scripts/gen-codes.mjs --check` and `test/gen-codes.test.mjs` fail when a mirror differs from what the registry generates.
4. To let another platform emit an existing code: `add-code.mjs --merge-clients --code <code> --clients <platform>`. To drop a client or change another field: `add-code.mjs --replace` with the whole entry. When a client is dropped, remap that platform's phase-1 points in `failure-codes.sources.json`; `test/registry.test.mjs` checks that a mapped point's platform emits its code.
5. Several units may run add-code at once. The lock is `contracts/.lock`: a run writes its owner file into a fresh temp directory and renames that directory to `.lock` in one atomic step, so a lock never exists without its owner and a failed write leaves no lock behind. Release moves the lock aside before deleting it. A run tries every 50 ms for up to 60 s, and a lock older than 120 s is taken to be from a run that died and is broken. Every file is written through a temp file in `contracts/` (git-ignored) and a rename, so a run that dies leaves nothing in an SDK source folder. A bad entry is refused before any wait for the lock. Only a new code gets an `added` record in `failure-codes.sources.json`; `--merge-clients` and `--replace` leave that file alone.
6. sellwild-widget vendors byte-equal copies of `failure-codes.json`, this file, `reference/log-failure.mjs`, the golden vectors, most schemas and the print gate (its `contracts/scripts/sync-check.mjs` lists them). After any of them changes, the widget runs `node contracts/scripts/sync-check.mjs --update`; its sha256 sync check fails until then.
7. Run `npm test` in `contracts/` and each platform's parity test.

## 5. The gate: `decideFailure`

`decideFailure(state, input, context, uid, now) -> { state, event | null, flushNow, reason }` is a pure function. The shell only reads flags, uid and clock, calls it, and pushes.

### 5.1 State

```
state = { sessionCount, keys: [ { key, lastEmitAt, suppressed, emits } ] }
```

`keys` is ordered from least to most recently used. "Touch" means move the entry to the end. A session is the process lifetime on iOS, Android, Flutter and core/RN JS, and one page view in the widget.

### 5.2 Order of steps

1. `coerceFlag(context.eventsEnabled, true)` is false → drop, reason `events_disabled`. This beats `fatal`.
2. `coerceFlag(context.failuresEnabled, true)` is false → drop, reason `failures_disabled`. This beats `fatal`.
3. Normalize: `action = normalizeCode(input.code)`, `label = normalizeComponent(input.component)`, `severity = normalizeSeverity(input.severity)`.
4. Sampling: when severity is not `fatal` and `isSampled(uid, coerceRate(context.failuresSampleRate))` is false → drop, reason `sampled_out`.
5. Session cap: `state.sessionCount >= 20` → drop, reason `session_capped`, state unchanged. Fatal failures are dropped too.
6. Build `errName` and the full sanitized message `msgFull` (section 7.5), then `key = dedupeKey(action, label, errName, msgFull)`.
7. If `key` is in `state.keys`:
   - `emits >= 3` → touch the entry, drop, reason `key_capped`.
   - `now - lastEmitAt < 60000` → `suppressed + 1`, touch, drop, reason `deduped`.
8. Emit:
   - `seq = sessionCount + 1`; `repeat = (existing suppressed, or 0) + 1`; `capped = (seq == 20)`.
   - The entry becomes `{ key, lastEmitAt: now, suppressed: 0, emits: previous emits + 1 }` and is touched.
   - When `keys` now holds more than 50 entries, the least recently used ones are removed.
   - `sessionCount = seq`.
   - `event = buildFailureEvent(...)` (section 6); `flushNow = (seq == 1 || severity == 'fatal')`; reason `null`.

A drop never changes state except in step 7.

### 5.3 Flag coercion: `coerceFlag(v, default)`

Same rule for `EVENTS_ENABLED` and `FAILURES_ENABLED` (and the existing EVENTS_ENABLED coercion):

| value | result |
|---|---|
| boolean | itself |
| number | `v != 0` |
| string | not one of `false`, `0`, `no`, `off` after ASCII trim and ASCII lower case. `''` is on. |
| null, absent, object, array | the default (true) |

ASCII trim removes U+0009–U+000D and U+0020 only.

### 5.4 Sample rate: `coerceRate(v)`

1. A finite number, or a string that after ASCII trim matches `^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$`, is clamped to [0, 1].
2. Anything else (null, `''`, NaN, `'50%'`, booleans, objects) is 1.

### 5.5 Sampling: `isSampled(uid, rate)`

1. `rate >= 1` → true; `rate <= 0` → false.
2. Otherwise `fnv1a32(utf8(uid + ":failures")) / 2^32 < rate` (strict). A non-string uid counts as `''`.
3. `fnv1a32`: offset basis `0x811c9dc5`, prime `0x01000193`, over the UTF-8 bytes (lone surrogates as U+FFFD), unsigned 32-bit.
4. The result depends only on uid and rate, so a session is sampled in or out as a whole. There is no cached decision: when flags load, the real rate applies from then on.

### 5.6 Dedupe key

`action + "|" + label + "|" + (errName or "") + "|" + first 64 code points of msgFull`

`msgFull` is the sanitized message before the 200 cut.

## 6. The event

### 6.1 Wire shape

One element of the existing events array. No server change.

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

1. `event` is always `clientFailure`. `action` is the code. `label` is the component.
2. `amount` is never used.
3. SDK queues still stamp `attributes.type` and `attributes.sdkVersion`. logFailure does not rely on them. `schemas/client-failure-event.schema.json#/$defs/wireEvent` allows them.
4. SDK queues must not overwrite `attributes.code` on a clientFailure event: logFailure sets it, cleaned and cut to 64 (6.3 row 1). Other events keep today's stamping. iOS `stampEvent` follows this; core `createEventQueue` stamps the partner code only under the event's own attributes, so the event's code wins; Android `buildBatchJson` (`SellwildAPI.kt`) does not yet, and the Android unit fixes it.

### 6.2 Fields

| field | source | rule |
|---|---|---|
| `action` | `input.code` | `normalizeCode`: exact format match (4.1), else `client.code.invalid`. |
| `label` | `input.component` | Exact match of `configure`, `remoteConfig`, `listings`, `localized`, `feed`, `banner`, `native`, `video`, `house`, `bridge`, `webview`, `widget`, `shorts`, `tv`, `flipcard`, `growthcode`, `geo`, `storage`, else `unknown`. Case sensitive. |
| `uid` | uid provider | The events queue uid, used as is. |
| `createdTime` | clock | Epoch ms. |

### 6.3 Attributes

Keys in this order; this list is also the allowlist. Every value is a string. At most 16 keys.

| # | key | source | rule |
|---|---|---|---|
| 1 | `code` | context.partnerCode | cleanText, cut to 64; empty → `unknown`. Always set by logFailure, never left to queue stamping, and never overwritten by it (6.1 item 4). |
| 2 | `client` | context.client | `core`, `react-native`, `ios`, `android`, `flutter`, `widget`, as set by the shell; missing or empty → `unknown`. |
| 3 | `clientVersion` | context.clientVersion | cleanText, cut to 32; empty → `unknown`. |
| 4 | `severity` | input.severity | `fatal`, `error`, `warn`; anything else → `error`. fatal = the surface could not render; error = the operation failed and a fallback was used; warn = degraded but handled. |
| 5 | `fv` | constant | `"1"`. |
| 6 | `errName` | input.errName | cleanText, cut to 64; empty → left out. |
| 7 | `msg` | message + errMessage | Section 7.5; cut to 200; empty → left out. |
| 8 | `stack` | input.stack | Section 7.4 (5 frames, 800); empty → left out. |
| 9 | `httpStatus` | input.httpStatus | Integer 100–999, or a string of exactly 3 digits after ASCII trim; else left out. |
| 10 | `host` | input.url | `hostOf(url)` (7.3), cut to 253; null → left out. The URL itself is never sent. |
| 11 | `zoneId` | input.zoneId | A string, or a safe integer written in decimal; cleanText, cut to 32; empty or other numbers → left out. |
| 12 | `wrapper` | context.wrapper | `react-native` or `flutter`, else left out. |
| 13 | `release` | context.release | Widget git sha; cleanText, cut to 64; empty → left out. |
| 14 | `seq` | gate | Decimal. |
| 15 | `repeat` | gate | Decimal, always present (`"1"` when nothing was folded in). |
| 16 | `capped` | gate | `"1"` on the 20th event of the session, else left out. |

Nothing else from the input reaches the event: unknown input fields are ignored.

### 6.4 Size budget

1. The size is the UTF-8 byte length of the canonical JSON of the whole event (`event`, `action`, `label`, `attributes`, `uid`, `createdTime`).
2. Canonical JSON: no whitespace; strings escape only `"` → `\"`, `\` → `\\`, U+0008 `\b`, U+000C `\f`, U+000A `\n`, U+000D `\r`, U+0009 `\t`, other U+0000–U+001F as `\u00xx` (lower-case hex); `/` and non-ASCII stay literal; `createdTime` as a decimal integer. Key order does not change the length. Do not measure with the platform JSON encoder (iOS escapes `/`).
3. Over 2048 bytes: drop `stack`. Still over: cut `msg` to 80. Still over: drop `msg`. Still over: send it as is.

## 7. Sanitizing

All lengths are Unicode code points (not UTF-16 units, not grapheme clusters).

### 7.1 `cleanText(s)`

1. Lone surrogates become U+FFFD.
2. These become a space: U+0000–U+001F, U+007F–U+009F, U+0020, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF.
3. Runs of spaces collapse to one; leading and trailing spaces are removed.

### 7.2 `truncateUnicode(s, max)`

1. If `s` has at most `max` code points, return it unchanged.
2. Else `k = max - 1` (room for `…` U+2026, which counts toward `max`).
3. While `k > 0` and (code point `k` is an extender, or code point `k - 1` is U+200D ZWJ): `k = k - 1`. Extenders: U+0300–036F, U+1AB0–1AFF, U+1DC0–1DFF, U+20D0–20FF, U+FE00–FE0F, U+FE20–FE2F, U+200D, U+1F3FB–1F3FF, U+E0020–E007F, U+E0100–E01EF. This drops a base character together with its combining marks, keeps emoji ZWJ sequences whole, and never ends on a ZWJ.
4. If `k > 0` and code point `k` is a regional indicator (U+1F1E6–1F1FF): count the regional indicators directly before `k`; if the count is odd, `k = k - 1` (never split a flag).
5. Return the first `k` code points + `…`.

### 7.3 `hostOf(url)`

1. Only strings. ASCII-trim.
2. `scheme://rest` where scheme matches `^[A-Za-z][A-Za-z0-9+.-]*$`, or `//rest`. Anything else → null.
3. The authority is the longest prefix of `rest` whose characters are not `/`, `?` or `#` and are ASCII letters, digits, one of `.-_~%!$&'*+,;=:@[]`, or any code point from U+0080 up.
4. Drop everything up to the last `@`.
5. Starts with `[`: IPv6 literal → `<ip>` if it contains `]`, else null.
6. Drop from the first `:` (port). Drop trailing dots. ASCII lower case.
7. Empty → null. Matches `^[0-9]{1,3}(\.[0-9]{1,3}){3}$` → `<ip>`.

### 7.4 Stack: `sanitizeStack(stack, errName)`

1. Split on U+000A, remove every U+000D, ASCII-trim each line, drop empty lines.
2. If `errName` is set and the first line equals it or starts with `errName + ":"`, drop that line (V8 header).
3. Keep the first 5 lines. Clean each with `cleanText`, then run this pattern once, left to right, first matching alternative wins, replaced text is not scanned again:

   ```
   ([A-Za-z][A-Za-z0-9+.-]*://[^ "'<>()]*)|(//[A-Za-z0-9-]+\.[^ "'<>()]*)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})|([^ ():]*/)|(\?[^ :()]*)
   ```

   | group | replacement |
   |---|---|
   | 1, 2 URL | `hostOf(match)`; when null, the text after the last `/` of the path (before `?`/`#`); when that is empty, `<url>` |
   | 3 email | `<email>` |
   | 4 UUID | `<id>` |
   | 5 IPv4 | `<ip>` |
   | 6 directory prefix | removed (paths become basenames) |
   | 7 query | removed |

4. Drop lines that end up empty. Join with U+000A. Cut to 800 (7.2). Nothing left → no stack.
5. Digit runs are not masked in stacks (they are line and column numbers).

### 7.5 Message

1. `sanitizeMessage(s)` = `cleanText(s)`, then one left-to-right pass of:

   ```
   ([A-Za-z][A-Za-z0-9+.-]*://[^ "'<>()]*)|(//[A-Za-z0-9-]+\.[^ "'<>()]*)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})|([0-9]{6,})
   ```

   | group | replacement |
   |---|---|
   | 1, 2 URL | `hostOf(match)`, or `<url>` when null |
   | 3 email | `<email>` |
   | 4 UUID | `<id>` |
   | 5 IPv4 | `<ip>` |
   | 6 six or more digits | `<n>` |

2. `a = sanitizeMessage(input.message)`, `b = sanitizeMessage(input.errMessage)` (non-strings give `''`).
3. `msgFull` = the non-empty values of `[a, b]` joined with `": "`, where `b` is left out when it equals `a`.
4. `msg` = `truncateUnicode(msgFull, 200)`; left out when `msgFull` is empty.

### 7.6 PII never sent

Listing titles and text, search keywords, user names, emails, phone numbers, IDFA/GAID or other device ids beyond the queue uid, IPs, lat/lon/zip/city, tcString and consent strings, eids, cookies, request or response bodies, host-page URLs, full URLs and query strings. The rules above enforce the parts they can; call sites must not pass the rest (for example, never pass a listing title as `message`).

## 8. Transport and flushing

1. The event goes through each platform's EXISTING queue to `events.sellwild.com/events/queue`:

   | platform | push | flush now |
   |---|---|---|
   | core | `eventQueue.push` | `pushNow` |
   | widget | `pushEvent` | `pushEventNow` |
   | iOS | `SellwildAPIClient.shared.sendEvent` | `sendEvent`, then `flushEvents` |
   | Android | `SellwildEventQueue.track` (needs an attributes parameter) | already sends at once |
   | Flutter | `sendEvent`, fire and forget | already sends at once |

2. `flushNow` is true for the first event of the session (`seq == 1`) and for `fatal`. Everything else rides normal batching.
3. The uid the pure core sees is the queue's own uid, so sampling and the wire agree.
4. Transport never reports itself (A7). These never call logFailure, and a test on each platform proves it: core `EventQueue.flush` (`core/src/event-queue.ts`, still exported from `api.ts` and the package index), widget `drainQueue`, iOS `flushEventsLocked`, Android `SellwildEventQueue.flush`, Flutter `sendEvent`. Failures of the events endpoint are never reported. The widget guards `localStorage` and `crypto` inside `getUid` (Events.ts) instead of reporting them.
5. The widget must NOT install `window.onerror` or `unhandledrejection` hooks: they would collect host-page errors. It calls logFailure only from its own catch sites.

## 9. Log once

1. Log each failure once, at the lowest layer that observes it.
2. Wrappers do not log it again:
   - React Native over core: `useSellwildListings`, `SellwildFeed`/`SellwildBanner` onError forwarders.
   - React Native over native: the native SDK logs; the RN bridge adds only `wrapper`.
   - Flutter over native (when hosted): same as React Native.
   - Feed views over their API client (`SellwildFeedView` on iOS/Android re-surfaces a listings failure the client already logged).
   - `configure()` falling back to defaults after a config fetch failure.
3. Existing events stay (A6): `adError`, `placementMismatch`, `errorAddingElement`, `customElementsNotSupported`, video `adError`/`adNoBids`. Where one marks a real failure, the site ALSO calls logFailure. Record each such site in the phase report.

## 10. Kill switches and CMS keys

1. `EVENTS_ENABLED` is the master switch (core `remote-config.ts`, iOS `SellwildEvents.isEnabled`, Android `SellwildEvents.isEnabled`; missing today in Flutter and the widget). Off drops every event, including clientFailure.
2. `FAILURES_ENABLED` and `FAILURES_SAMPLE_RATE` are new keys. Add them to core KEY_MAP and SellwildConfig, iOS/Android remote parsing, Flutter configure, the widget theme, and the CMS schemas (`sellwild-widget/cms/src/configs/app.ts` for mobile, `widgets.ts` for web). `schemas/app-config.schema.json` declares all three.
3. Core must call `eventQueue.setEnabled(config.eventsEnabled)`. Nothing does today.

## 11. Print gate

`scripts/print-gate.mjs` and `test/print-gate.test.mjs` enforce sections 1 and 2 on shipped SDK source.

1. Scanned: `core/src`, `react-native/src`, `react-native/ios`, `react-native/android/src`, `ios/Sources`, `android/src/main`, `flutter/lib`. Test folders and `*.test.*`/`*.spec.*` files are skipped.
2. Comments are ignored. Strings are code in TS (page scripts built in template strings are JS); in Swift, Kotlin, Dart and ObjC the native rules see code only and the JS rules below see string contents (scripts injected into the WebView).
3. Counted as prints:
   - TS/JS: `console.log|error|warn|info|debug|trace(`.
   - Swift: `print(`, `debugPrint(`, `dump(`, `NSLog(`, `os_log(` (not `x.print(`).
   - Kotlin/Java: `Log.e|w|i|d|v|wtf(`, `println(`, `print(`, `.printStackTrace(`, `System.out|err.print…`.
   - Dart: `print(`, `debugPrint(`.
   - ObjC: `NSLog(`.
4. Counted as empty catches (whitespace or comments only in the body):
   - TS/JS: `catch {}`, `catch (e) {}`, `.catch(() => {})`, `.catch((e) => undefined|null|void 0)`.
   - Swift: `catch {}`, `catch let e as T {}` and every other catch clause with an empty body.
   - Kotlin/Java: `catch (e: T) {}`.
   - Dart: `catch (_) {}`, `} on T {}`, `.catchError((_) {})`, `.catchError((e) => null)`.
   - ObjC: `@catch (…) {}`.
5. The eight A2 files (section 2) may print; they may not swallow.
6. `print-gate.allowlist.json` records each file's counts on 2026-09-23. The gate fails when any count goes up or a file not listed has a hit. When you remove hits, lower the counts in the same change: `node scripts/print-gate.mjs --update` (it refuses to raise a count unless `--allow-increase` is passed, which needs a reviewer).

## 12. Golden vectors (A5)

1. Every platform's pure core must reproduce every vector in `golden/log-failure.vectors.json` exactly: the same `event` (deep equal) or null, the same `flushNow`, the same `reason`, and the same `stateAfter`.
2. A vector is `{ name, input, context, stateBefore, expected: { event, flushNow, reason, stateAfter } }`. `context.uid` and `context.now` are the uid and clock for the call. `units` holds single-function tables (fnv1a32, truncateUnicode, hostOf, sanitizeMessage, coerceFlag, coerceRate, normalizeCode, normalizeHttpStatus) for porting.
3. `golden/log-failure.utf16.vectors.json` has inputs with lone UTF-16 surrogates. TS, Kotlin and Dart run it. Swift strings cannot hold lone surrogates and Foundation's JSON parser rejects them, so iOS skips it.
4. The widget vendors both files with a sha256 sync check.
5. Porting notes:
   - Match codes against the whole string (Kotlin `matches`/`matchEntire`; Swift full-range anchored match). Java and ICU `$` also match before a final newline; the `[a-z0-9_.]` charset check in the reference closes that gap.
   - The two patterns use only ASCII classes, greedy quantifiers and ordered alternation. JS, Java/Kotlin, ICU (NSRegularExpression) and Dart give the same matches. Do not add flags (no Unicode, case-insensitive or multiline mode). Swift must convert NSRange offsets (UTF-16) correctly.
   - Count code points: JS `[...s]`, Kotlin `codePointCount`, Swift `unicodeScalars`, Dart `runes`.
   - JSON booleans are not numbers: `coerceRate(false)` is 1, not 0. On iOS tell `CFBoolean` from `NSNumber`.
   - Missing keys and JSON null are the same for every input and context field.

## 13. Tests never touch the network (A8)

1. TS and widget: unless a test installs its own, global `fetch` is replaced by a stub that returns a rejected promise, and `navigator.sendBeacon`, `XMLHttpRequest` and `WebSocket` by stubs that throw. The error text is each package's own: core and React Native use `network blocked in tests: <url>`; the widget's is in sellwild-widget `test/setup/network.ts`. Only each package's own harness test pins its text.
2. iOS: a `URLProtocol` registered for the whole test bundle fails every request.
3. Android: `URL.setURLStreamHandlerFactory` (once per JVM) or an equivalent fails http/https, plus injectable senders.
4. Flutter: an injected `http.Client` (`MockClient`); flutter_test's default `HttpOverrides` stays in place.
5. `contracts/`: tests never hit the network; `scripts/refresh-samples.mjs` needs `CONTRACTS_LIVE=1`, allows GET only to `widget.sellwild.com/app/*`, `cache.sellwild.com/*` and `sellwild-sports-cache.s3.us-east-1.amazonaws.com/*`, and refuses `events.sellwild.com`.

## 14. Behavior-change policy (A9)

1. Fix a bug only if it throws, crashes, or yields an obviously invalid value (for example the string "null" used as a URL) AND a test proves it. Record each fix as a behavior change: file, before, after, why.
2. Cross-platform semantic drift (IAB_CATS scalar handling, MOBILE_ZID_* per OS, S2S_CONFIG text vs object, Android bidder passthrough of non-bidder keys) is NOT changed in this program. It is recorded in `expectations/drift/<platform>.json`, one file per SDK platform (`core`, `react-native`, `ios`, `android`, `flutter`; the widget keeps its own in sellwild-widget):
   - `expectations` maps each expectations file (`app-config`, `listings-response`) and case file to text that names every field that differs, as `field: why`. A conformance test passes a case when the platform matches `expected`, or differs only in a field its entry names; a named field that matches fails the test, so the entry is removed in the change that fixes the drift.
   - `other` records verified drift that no expectations case pins, keyed by a short topic (for example `bridge.android`).
   - Each platform unit edits only its own file. `test/expectations.test.mjs` checks that every entry names a real case and a field that platform is held to.
   - Which tests enforce the files today: only core. `core/test/conformance.test.ts` loads `drift/core.json` and fails when a named field matches. iOS (`SellwildConfigureTests`), Android (`SellwildListingsParserDeviceJsonTest`) and Flutter (`sellwild_models_test.dart`, `sellwild_api_test.dart`, `sellwild_sdk_configure_failures_test.dart`) read the expectations files for a few fields and do not load their drift file yet, so their entries are records that only `test/expectations.test.mjs` checks. React Native has only `other` entries. A platform unit that makes its conformance test compare a drifting field loads its own drift file and follows the rule above.
3. Never change SDK version numbers or release files (podspec, Package.swift pins, pubspec version, gradle version names).

## 15. Coverage summary (A10)

Every platform writes `<repo>/coverage-summary/<platform>.json`:

```json
{
  "platform": "ios",
  "generatedAt": "<ISO time>",
  "tool": "xccov+llvm-cov",
  "commands": ["..."],
  "gate": { "include": ["globs"], "lines": {"covered":0,"total":0,"pct":0}, "branches": null, "regions": {"covered":0,"total":0,"pct":0}, "functions": {"covered":0,"total":0,"pct":0} },
  "whole": { "lines": {}, "branches": null, "regions": {}, "functions": {} },
  "excluded": [ { "path": "glob", "reason": "why this is honestly not unit-testable, or 'dead: pending delete decision'" } ],
  "perFile": [ { "path": "...", "lines": 0.0, "branches": null, "functions": 0.0, "inGate": true } ]
}
```

1. Gate target: 95% lines AND 95% branches (regions on Swift, which has no branch data) AND 95% functions on the gate include list. `whole` is always reported next to it.
2. Exclusions only for: type-only files, generated or build output, entry bootstraps of about 15 lines or fewer, third-party SDK init bodies that need a real device or network, and dead code pending the user's delete decision. Every exclusion has a reason.

## 16. Checklist for a platform lane

1. Pure core at the A2 path, reproducing both vector files (iOS: the main file only).
2. Shell with the A3 names, reentrancy guard, never-throw wrapper, debug echo and the input cap (3.3 item 4).
3. Registry mirror plus parity test against `failure-codes.json`.
4. A test that the transport functions in 8.4 never call logFailure.
5. Network blocked in tests (section 13).
6. Print gate stays green; lower the allowlist as prints go away.
7. Factory output emitted to `contracts/out/<platform>/<schema>.<variant>.json` and checked with `node contracts/scripts/validate.mjs --out <platform>`.

## 17. Decisions this document adds

The proposal and amendments left these open. The reference implements them and the vectors pin them.

1. IPv4 addresses (in messages, stacks and URL hosts) become `<ip>`, and IPv6 URL hosts too. This enforces "never send IP".
2. Protocol-relative URLs (`//host/path`, the widget's default listings URL form) are treated as URLs. A URL with no host (`file:///…`) becomes `<url>` in messages and its basename in stacks.
3. `message` and the error message are both kept, joined with `": "`.
4. Context strings are bounded: partner code 64, clientVersion 32, release 64, host 253. After the three budget steps an event that is still over 2048 bytes is sent as is.
5. Step order inside the gate: the session cap is checked before dedupe, and the per-key cap before the dedupe window. Only bookkeeping differs from the proposal's listing order; the emitted events are the same.
6. Sampling is recomputed from uid and rate on every call instead of cached, so a rate that arrives with the remote config applies from then on.
7. Stacks drop the engine header line, reduce paths to basenames, remove query strings, and do not mask digit runs.
8. A code is valid by format alone; the registry is not consulted at runtime.
9. `localized.fetch.*` codes are for iOS, Android and the widget only: core and React Native resolve the localized config but do not fetch the cache.
10. Registry severity is a recommendation; logFailure defaults to `error`.
11. Every shell caps message and error message at 1000 UTF-16 units and the stack at 2000 before the pure core (3.3 item 4); TS drops the V8 header first when the stack is over the cap.
12. SDK queues never overwrite a clientFailure's `attributes.code` (6.1 item 4).
