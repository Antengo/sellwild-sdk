// Failure codes the TS core and React Native report: the entries of
// contracts/failure-codes.json whose `clients` include `core` or
// `react-native` (React Native re-exports core), in registry order.
// test/failures-registry.test.ts checks this list against the JSON, so add a
// code to both in the same change (contracts/FAILURES.md 4.4).
//
// Format: `<area>.<operation>.<reason>`. The registry's `component` and
// `severity` are what a call site usually passes; each call site decides.

export const FAILURE_CODES = [
  /**
   * A script inside the banner HTML (gpt.js or the zone script) failed to load.
   * Usually `banner`, `error`.
   */
  'ad.banner_script.network',
  /**
   * The requested ad size is missing or not numeric, which gives a 0x0 or NaN slot.
   * Usually `banner`, `warn`.
   */
  'ad.size.invalid',
  /**
   * A WebView bridge message had a missing or wrong-typed field (type, url, listing, zoneId,
   * message).
   * Usually `bridge`, `warn`.
   */
  'bridge.message.invalid',
  /**
   * A WebView bridge message was not valid JSON.
   * Usually `bridge`, `warn`.
   */
  'bridge.message.parse',
  /**
   * The SellwildRNModule native module is not registered, so native commands are no-ops.
   * Usually `bridge`, `warn`.
   */
  'bridge.native_module.missing',
  /**
   * A native view manager (banner or feed) is not registered, so the React Native view renders
   * nothing.
   * Usually `bridge`, `error`.
   */
  'bridge.native_view.missing',
  /**
   * The widget page reported a JavaScript error through the bridge ERROR message.
   * Usually `webview`, `error`.
   */
  'bridge.script.exception',
  /**
   * Replacement action when a call site passes a code that fails the registry format. The label
   * keeps the caller component. Never pass it directly.
   * Usually `unknown`, `error`.
   */
  'client.code.invalid',
  /**
   * AD_STACK or an AD_STACK_BY_ZONE entry is not a known mode (or not a map); the default is used.
   * Usually `remoteConfig`, `warn`.
   */
  'config.adstack.invalid',
  /**
   * A BANNER_SIZES entry could not be parsed or has non-positive dimensions; it was dropped.
   * Usually `remoteConfig`, `warn`.
   */
  'config.banner_sizes.invalid',
  /**
   * The remote config request returned a non-2xx status (a missing file returns 403 AccessDenied
   * XML).
   * Usually `remoteConfig`, `error`.
   */
  'config.fetch.http',
  /**
   * The remote config request failed at the network level (DNS, offline, TLS, reset).
   * Usually `remoteConfig`, `error`.
   */
  'config.fetch.network',
  /**
   * The remote config body is not valid JSON.
   * Usually `remoteConfig`, `error`.
   */
  'config.fetch.parse',
  /**
   * The remote config request did not answer within the client timeout.
   * Usually `remoteConfig`, `error`.
   */
  'config.fetch.timeout',
  /**
   * A config field has an unexpected type or value and was ignored or coerced.
   * Usually `remoteConfig`, `warn`.
   */
  'config.field.invalid',
  /**
   * The remote config JSON is valid but not an object (array, string or null).
   * Usually `remoteConfig`, `error`.
   */
  'config.parse.invalid',
  /**
   * GrowthCode is enabled but the partner id or sync URL is missing, so the sync cannot run.
   * Usually `growthcode`, `warn`.
   */
  'growthcode.config.missing',
  /**
   * The GrowthCode eid blob is not an array, or entries lack source/uids/id; they were dropped.
   * Usually `growthcode`, `warn`.
   */
  'growthcode.eid.invalid',
  /**
   * The GrowthCode eid blob (eb) is not valid JSON.
   * Usually `growthcode`, `warn`.
   */
  'growthcode.eid.parse',
  /**
   * The GrowthCode sync response is valid JSON but not an object.
   * Usually `growthcode`, `warn`.
   */
  'growthcode.sync.invalid',
  /**
   * The listings GET returned a non-2xx status.
   * Usually `listings`, `error`.
   */
  'listings.fetch.http',
  /**
   * The listings GET failed at the network level (DNS, offline, TLS, reset).
   * Usually `listings`, `error`.
   */
  'listings.fetch.network',
  /**
   * The listings body is not valid JSON (for example an HTML error page).
   * Usually `listings`, `error`.
   */
  'listings.fetch.parse',
  /**
   * Listings GET did not answer within the client timeout.
   * Usually `listings`, `error`.
   */
  'listings.fetch.timeout',
  /**
   * A listing item or one of its fields (photo, price, currency) has an unexpected shape; it was
   * dropped or hidden.
   * Usually `listings`, `warn`.
   */
  'listings.item.invalid',
  /**
   * The listings JSON is valid but has no result.rs array.
   * Usually `listings`, `error`.
   */
  'listings.parse.invalid',
  /**
   * The tag-cache listings response is not an array.
   * Usually `listings`, `error`.
   */
  'listings.tag_cache.invalid',
  /**
   * The tag-cache listings request failed.
   * Usually `listings`, `warn`.
   */
  'listings.tag_cache.network',
  /**
   * LOCALIZED_LISTINGS is set but not an object, or lacks baseUrl/urlTemplate; the feature is off.
   * Usually `localized`, `warn`.
   */
  'localized.config.invalid',
  /**
   * LOCALIZED_LISTINGS holds JSON text that could not be parsed; the feature is off.
   * Usually `localized`, `warn`.
   */
  'localized.config.parse',
  /**
   * The widget never signaled that it loaded (bridge down, partner.js failed); the spinner never
   * ends.
   * Usually `webview`, `error`.
   */
  'widget.load.timeout',
  /**
   * A script the widget needs (partner.js, hls.js, a variant bundle) failed to load.
   * Usually `widget`, `fatal`.
   */
  'widget.script_load.network',
  /**
   * The widget WebView failed to load its page or a main resource (offline, DNS, TLS, navigation
   * failure).
   * Usually `webview`, `error`.
   */
  'widget.webview_load.network',
] as const

/** A registry code this package may pass to logFailure. */
export type FailureCode = (typeof FAILURE_CODES)[number]
