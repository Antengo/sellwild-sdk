// Flutter mirror of contracts/failure-codes.json (FAILURES.md 4.2): every code
// whose `clients` include `flutter`, plus the component and severity values
// logFailure accepts. test/failures/failure_codes_parity_test.dart checks this
// file against the JSON.
//
// To add a code, add it to failure-codes.json first (FAILURES.md 4.4), then
// here and to [SellwildFailureCode.all], in registry order.
//
// Constants only: no executable lines, so it is excluded from coverage.
// coverage:ignore-file constants only no executable lines

/// Failure codes for [SellwildFailures.log], `<area>.<operation>.<reason>`.
abstract final class SellwildFailureCode {
  /// The banner has neither a GAM tag nor a zone id, so it renders a blank
  /// slot.
  static const String adBannerConfigMissing = 'ad.banner_config.missing';

  /// A script inside the banner HTML (gpt.js or the zone script) failed to
  /// load.
  static const String adBannerScriptNetwork = 'ad.banner_script.network';

  /// googletag.defineSlot failed or returned null (bad GAM path), so nothing
  /// renders.
  static const String adGptSlotInvalid = 'ad.gpt_slot.invalid';

  /// A WebView bridge message had a missing or wrong-typed field (type, url,
  /// listing, zoneId, message).
  static const String bridgeMessageInvalid = 'bridge.message.invalid';

  /// A WebView bridge message was not valid JSON.
  static const String bridgeMessageParse = 'bridge.message.parse';

  /// A WebView bridge message had an unknown type.
  static const String bridgeMessageUnsupported = 'bridge.message.unsupported';

  /// The widget page reported a JavaScript error through the bridge ERROR
  /// message.
  static const String bridgeScriptException = 'bridge.script.exception';

  /// Replacement action when a call site passes a code that fails the registry
  /// format. The label keeps the caller component. Never pass it directly.
  static const String clientCodeInvalid = 'client.code.invalid';

  /// AD_STACK or an AD_STACK_BY_ZONE entry is not a known mode (or not a map);
  /// the default is used.
  static const String configAdstackInvalid = 'config.adstack.invalid';

  /// Applying the fetched config threw; defaults are kept.
  static const String configApplyException = 'config.apply.exception';

  /// A configured color string is not a valid color; the fallback color is
  /// used.
  static const String configColorInvalid = 'config.color.invalid';

  /// The remote config request returned a non-2xx status (a missing file
  /// returns 403 AccessDenied XML).
  static const String configFetchHttp = 'config.fetch.http';

  /// The remote config request failed at the network level (DNS, offline, TLS,
  /// reset).
  static const String configFetchNetwork = 'config.fetch.network';

  /// The remote config body is not valid JSON.
  static const String configFetchParse = 'config.fetch.parse';

  /// The remote config request did not answer within the client timeout.
  static const String configFetchTimeout = 'config.fetch.timeout';

  /// A config field has an unexpected type or value and was ignored or coerced.
  static const String configFieldInvalid = 'config.field.invalid';

  /// The host app's overrides callback threw during configure.
  static const String configOverridesException = 'config.overrides.exception';

  /// The remote config JSON is valid but not an object (array, string or null).
  static const String configParseInvalid = 'config.parse.invalid';

  /// AD_REFRESH_INTERVAL looks like seconds rather than milliseconds.
  static const String configRefreshIntervalInvalid =
      'config.refresh_interval.invalid';

  /// The remote config URL could not be built from partnerCode and slug.
  static const String configUrlInvalid = 'config.url.invalid';

  /// A listing photo failed to download.
  static const String feedImageNetwork = 'feed.image.network';

  /// The listings client was released or disposed while a request was in
  /// flight.
  static const String listingsClientMissing = 'listings.client.missing';

  /// The listings GET returned a non-2xx status.
  static const String listingsFetchHttp = 'listings.fetch.http';

  /// The listings GET failed at the network level (DNS, offline, TLS, reset).
  static const String listingsFetchNetwork = 'listings.fetch.network';

  /// The listings body is not valid JSON (for example an HTML error page).
  static const String listingsFetchParse = 'listings.fetch.parse';

  /// Listings GET did not answer within the client timeout.
  static const String listingsFetchTimeout = 'listings.fetch.timeout';

  /// A listing item or one of its fields (photo, price, currency) has an
  /// unexpected shape; it was dropped or hidden.
  static const String listingsItemInvalid = 'listings.item.invalid';

  /// Decoding a listing item threw (strict casts on real payloads).
  static const String listingsItemParse = 'listings.item.parse';

  /// The listings JSON is valid but has no result.rs array.
  static const String listingsParseInvalid = 'listings.parse.invalid';

  /// A host app callback (onLoad, onListingTap, onAdImpression, onError) threw
  /// inside the SDK.
  static const String widgetHostCallbackException =
      'widget.host_callback.exception';

  /// The widget never signaled that it loaded (bridge down, partner.js failed);
  /// the spinner never ends.
  static const String widgetLoadTimeout = 'widget.load.timeout';

  /// A script the widget needs (partner.js, hls.js, a variant bundle) failed to
  /// load.
  static const String widgetScriptLoadNetwork = 'widget.script_load.network';

  /// The widget WebView failed to load its page or a main resource (offline,
  /// DNS, TLS, navigation failure).
  static const String widgetWebviewLoadNetwork = 'widget.webview_load.network';

  /// Every code above, in registry order.
  static const List<String> all = [
    adBannerConfigMissing,
    adBannerScriptNetwork,
    adGptSlotInvalid,
    bridgeMessageInvalid,
    bridgeMessageParse,
    bridgeMessageUnsupported,
    bridgeScriptException,
    clientCodeInvalid,
    configAdstackInvalid,
    configApplyException,
    configColorInvalid,
    configFetchHttp,
    configFetchNetwork,
    configFetchParse,
    configFetchTimeout,
    configFieldInvalid,
    configOverridesException,
    configParseInvalid,
    configRefreshIntervalInvalid,
    configUrlInvalid,
    feedImageNetwork,
    listingsClientMissing,
    listingsFetchHttp,
    listingsFetchNetwork,
    listingsFetchParse,
    listingsFetchTimeout,
    listingsItemInvalid,
    listingsItemParse,
    listingsParseInvalid,
    widgetHostCallbackException,
    widgetLoadTimeout,
    widgetScriptLoadNetwork,
    widgetWebviewLoadNetwork,
  ];
}

/// What failed: the `label` of a clientFailure event. Anything else is sent
/// as `unknown`.
abstract final class SellwildFailureComponent {
  static const String configure = 'configure';
  static const String remoteConfig = 'remoteConfig';
  static const String listings = 'listings';
  static const String localized = 'localized';
  static const String feed = 'feed';
  static const String banner = 'banner';
  static const String native = 'native';
  static const String video = 'video';
  static const String house = 'house';
  static const String bridge = 'bridge';
  static const String webview = 'webview';
  static const String widget = 'widget';
  static const String shorts = 'shorts';
  static const String tv = 'tv';
  static const String flipcard = 'flipcard';
  static const String growthcode = 'growthcode';
  static const String geo = 'geo';
  static const String storage = 'storage';
}

/// How bad a failure is. [SellwildFailures.log] uses [error] when none is
/// given.
abstract final class SellwildFailureSeverity {
  /// The surface could not render.
  static const String fatal = 'fatal';

  /// The operation failed and a fallback was used.
  static const String error = 'error';

  /// Degraded but handled.
  static const String warn = 'warn';
}
