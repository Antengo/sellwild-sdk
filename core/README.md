# @sellwild/sdk-core

Core types, API client, and ad configuration for the Sellwild mobile advertising SDK.

This package provides the shared foundation used by [`@sellwild/react-native-sdk`](https://www.npmjs.com/package/@sellwild/react-native-sdk) and the Sellwild web widget. You typically don't install this directly — it's included as a dependency of the platform SDKs.

## What's Inside

- **`SellwildConfig`** — Full SDK configuration type
- **`configure()`** — Fetch the partner's remote config and build a full config (the 1.2.0+ entry point)
- **`buildConfig()`** — Build a config from partial options with sensible defaults
- **`fetchListings()`** — Fetch marketplace listings from the Sellwild API
- **`fetchTagCacheListings()`** — Fetch listings by keyword tags
- **`eventQueue`** / **`createEventQueue()`** — Analytics event batching and delivery
- **`logFailure()`** / **`setFailureContext()`** — Failure reporting (see below)
- **`getAdPlacements()`** — Generate ad placement configurations from config

## configure() and the kill switches

`configure(partnerCode, slug, options)` sets the partner for events and failure reports first, then fetches `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`. After the fetch it applies three remote keys:

| Key | What it does | Default |
|---|---|---|
| `EVENTS_ENABLED` | Master switch for every event. `configure()` now passes it to `eventQueue.setEnabled()`, so `false` stops all event POSTs, failure reports included. | on |
| `FAILURES_ENABLED` | Turns failure reports off without touching other events. A local `failuresEnabled` override wins. | on |
| `FAILURES_SAMPLE_RATE` | Share of sessions that send failure reports, `0` to `1`. A number or decimal text; anything else counts as `1`. | `1` |

The flags accept `true`/`false`, numbers (`0` is off) or text (`false`, `0`, `no` and `off` are off, trimmed, any case). `buildConfigWithRemote()` applies them the same way.

If the fetch fails, `configure()` still returns a config built from the defaults. The fetch reports its own failure; `configure()` does not report it again.

A config value `configure()` has to ignore or coerce (an unknown `AD_STACK`, say) is reported only after these flags are applied. So a config that turns events or failures off sends no report about itself.

## Failure reporting

Every failure the SDK handles (a network error, a bad HTTP status, JSON that does not parse, a config value it has to ignore) is reported once as a `clientFailure` event through the events queue. The contract is `contracts/FAILURES.md` in the SDK repo; the codes are in `contracts/failure-codes.json`.

```ts
import { logFailure } from '@sellwild/sdk-core'

try {
  await loadSomething()
} catch (error) {
  logFailure({ code: 'listings.fetch.network', component: 'listings', error, url })
}
```

- **`logFailure(input)`** takes `code` (a registry code), `component`, and optional `severity` (`fatal`, `error` (default) or `warn`), `error`, `message`, `httpStatus`, `url` and `zoneId`. It never throws, never waits on the network and returns nothing. Only the host of `url` is sent. Messages are cleaned of URLs, emails, ids and long numbers before they leave the device. Repeats of the same failure within a minute are folded into one event, and a session sends at most 20.
- **`setFailureContext(partial)`** merges into the context every report carries: `partnerCode`, `client`, `clientVersion`, `debug`, `eventsEnabled`, `failuresEnabled`, `failuresSampleRate`, `wrapper`, plus `now`, `uid` and `sink` for tests. `configure()` sets it for you. A field set to `undefined` goes back to its default.
- **`debug: true`** (in the context, or `setDebugLogging(true)`) prints one `[Sellwild] failure ...` line per report. Other trace output goes through `debugLog()`, which also prints only when debug is on.
- **`resetFailuresForTests()`** and **`getFailureInternalErrors()`** are for tests.
- A JSON parse error is sent by its name only (`SyntaxError`). Its message quotes part of the text that did not parse, which is a response body or an EID blob, and those are never sent.

Pure helpers return what went wrong instead of reporting it, for hosts that report on their own: `mapRemoteConfigWithIssues`, `parseEidBlobWithIssues`, `parseGrowthCodeResponseWithIssues`, `resolveGrowthCodeWithIssues` and `resolveLocalizedListingsWithIssues`. The plain `parseEidBlob`, `parseGrowthCodeResponse`, `resolveGrowthCode` and `resolveLocalizedListings` report those issues and return the same result as always. `mapRemoteConfig` stays pure.

`fetchRemoteConfigWithIssues` fetches like `fetchRemoteConfig` and reports a failed load, but hands back the config's value issues instead of reporting them. `fetchRemoteConfig` reports them itself with `logFailuresWithFlags(flags, inputs)`: each one goes out only when both the fetched config's `EVENTS_ENABLED`, `FAILURES_ENABLED` and `FAILURES_SAMPLE_RATE` and the failure context allow it, at the lower sample rate. The failure context does not change, so fetching a config never turns reports on or off for anything else, and a local `failuresEnabled` override from `configure()` still holds. `strictestFailureFlags(a, b)` is the pure rule it uses.

Other pure helpers: `getDefaultConfig()` (a copy of the defaults), `mergeConfig(defaults, ...layers)`, `classifyFetchError()`, and for the events queue `capQueue`, `takeBatch`, `requeueFailedBatch`, `resolveUid` and `stampEventAttributes`.

## Events queue

`eventQueue` is the shared queue: it batches events and POSTs them to `https://events.sellwild.com/events/queue` every 10 seconds (100 per batch, at most 1,000 held). `setPlatform()` stamps the host platform and `setPartnerCode()` the partner into each event.

`createEventQueue(deps)` builds a separate queue. The dependencies are `fetch`, `now`, `setTimeout`, `clearTimeout`, `randomUUID`, `random` (the uid fallback when `randomUUID` throws, as on Hermes) and `url`. Each one you leave out uses the global of the same name, and `url` defaults to the events endpoint:

```ts
const queue = createEventQueue({
  fetch: (url, init) => myFetch(url, init),
  now: () => clock.now(),
  url: 'https://events.example/queue',
})
```

The queue never reports its own failures: a report about the events endpoint would go to the same endpoint.

## Documentation

Full SDK docs: [sdk.sellwild.com](https://sdk.sellwild.com)
