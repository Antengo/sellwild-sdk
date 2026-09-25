import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'failures/sellwild_failure_code.dart';
import 'failures/sellwild_failures.dart';
import 'listing_json.dart';
import 'sellwild_config.dart';
import 'sellwild_models.dart';

/// Sellwild API client for fetching listings and sending analytics.
class SellwildAPIClient {
  /// The client the SDK uses. [SellwildSDK.configure] sets its [partnerCode]
  /// and [eventsEnabled].
  static SellwildAPIClient get instance => _instance;

  /// Replaces [instance], so a test can inject an http.Client. Tests only.
  @visibleForTesting
  static set instance(SellwildAPIClient client) => _instance = client;

  static SellwildAPIClient _instance = SellwildAPIClient();

  /// [client] defaults to a real http.Client, [clock] (epoch milliseconds) to
  /// the wall clock and [uid] to [processUid].
  SellwildAPIClient({http.Client? client, int Function()? clock, String? uid})
      : _http = client ?? http.Client(),
        _clock = clock ?? _wallClock,
        uid = uid ?? processUid;

  /// A random (v4) UUID made once per process: the events uid, so every
  /// event of a session carries the same one.
  static final String processUid = uuidV4(Random.secure());

  /// A random (version 4, RFC 4122 variant) UUID in lower-case hex, from
  /// [random]. Pure given [random], so tests can seed it.
  @visibleForTesting
  static String uuidV4(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  final _cache = <String, SellwildListingsResponse>{};
  final http.Client _http;
  final int Function() _clock;
  var _closed = false;
  var _failedEventSends = 0;

  /// The uid [sendEvent] uses when the caller passes none.
  final String uid;

  /// Partner code stamped as `attributes.code` on events that have none: the
  /// events pipeline keys partners on it. Set by configure before its fetch.
  String? partnerCode;

  /// Analytics kill switch (remote EVENTS_ENABLED). When false, [sendEvent]
  /// sends nothing. Set by configure from the resolved config.
  bool eventsEnabled = true;

  /// Events whose POST failed or was answered with a non-2xx status. The
  /// transport never reports them (FAILURES.md 8.4); tests read the count.
  @visibleForTesting
  int get failedEventSends => _failedEventSends;

  /// Fetches the listings cache for [config]. Each failure is reported once
  /// here through logFailure, then thrown to the caller as before. Items that
  /// cannot be read are reported and dropped; the rest are returned.
  Future<SellwildListingsResponse> fetchListings(SellwildConfig config) async {
    final url = config.effectiveListingsUrl;
    final cached = _cache[url];
    if (cached != null) return cached;

    // Parsed before the fetch, so text that is no URL (LISTINGS is remote
    // text) is listings.url.invalid, not a network failure. The same
    // FormatException is thrown to the caller as before.
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException catch (e) {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsUrlInvalid,
        component: SellwildFailureComponent.listings,
        error: e,
        message: 'listings URL is not a valid URL',
      );
      rethrow;
    }

    final http.Response response;
    try {
      response = await _http.get(uri);
    } catch (e) {
      SellwildFailures.log(
        code: _closed
            ? SellwildFailureCode.listingsClientMissing
            : e is TimeoutException
                ? SellwildFailureCode.listingsFetchTimeout
                : SellwildFailureCode.listingsFetchNetwork,
        component: SellwildFailureComponent.listings,
        severity: _closed ? SellwildFailureSeverity.warn : null,
        error: e,
        url: url,
      );
      rethrow;
    }
    if (response.statusCode != 200) {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsFetchHttp,
        component: SellwildFailureComponent.listings,
        message: 'HTTP ${response.statusCode}',
        httpStatus: response.statusCode,
        url: url,
      );
      throw SellwildException('HTTP ${response.statusCode} from $url');
    }

    final Object? data;
    try {
      data = jsonDecode(response.body);
    } on FormatException catch (e) {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsFetchParse,
        component: SellwildFailureComponent.listings,
        error: e,
        url: url,
      );
      rethrow;
    }

    final SellwildListingsResponse res;
    try {
      res = _parseListings(data, url);
    } on TypeError catch (e) {
      // The JSON is valid but not the cache's shape (FAILURES.md 4.1 invalid).
      SellwildFailures.log(
        code: SellwildFailureCode.listingsParseInvalid,
        component: SellwildFailureComponent.listings,
        error: e,
        url: url,
      );
      rethrow;
    }
    _cache[url] = res;
    return res;
  }

  // Throws TypeError when the body, `result`, `rs`, `config` or
  // `widgetCacheVersionId` has the wrong type. Every cast runs before any
  // report here, so one body is reported once.
  SellwildListingsResponse _parseListings(Object? decoded, String url) {
    final data = decoded as Map<String, dynamic>;
    final result = (data['result'] as Map<String, dynamic>?) ?? data;
    final rsJson = result['rs'] as List?;
    final configMap = (result['config'] as Map<String, dynamic>?) ?? {};
    final versionId = result['widgetCacheVersionId'] as String?;

    if (rsJson == null) {
      // No result.rs array: an empty feed, as before, but reported.
      SellwildFailures.log(
        code: SellwildFailureCode.listingsParseInvalid,
        component: SellwildFailureComponent.listings,
        message: 'no result.rs array',
        url: url,
      );
    }
    final rs = rsJson?.whereType<Map<String, dynamic>>().toList() ?? [];
    final dropped = (rsJson?.length ?? 0) - rs.length;
    if (dropped > 0) {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsItemInvalid,
        component: SellwildFailureComponent.listings,
        severity: SellwildFailureSeverity.warn,
        message: '$dropped result.rs entries are not objects; dropped',
        url: url,
      );
    }

    // An item fromJson cannot read is dropped, so one bad item no longer
    // fails the whole feed. All of them are reported once, with the first
    // error.
    final listings = <SellwildListing>[];
    Object? firstError;
    var failed = 0;
    var droppedPhotos = 0;
    for (final item in rs) {
      try {
        listings.add(SellwildListing.fromJson(item));
        droppedPhotos += nonObjectPhotoCount(item);
      } catch (e) {
        failed++;
        firstError ??= e;
      }
    }
    if (droppedPhotos > 0) {
      // fromJson skips photos entries that are not objects (as before); the
      // rest of the item is kept.
      SellwildFailures.log(
        code: SellwildFailureCode.listingsItemInvalid,
        component: SellwildFailureComponent.listings,
        severity: SellwildFailureSeverity.warn,
        message: '$droppedPhotos photos entries are not objects; dropped',
        url: url,
      );
    }
    if (failed > 0) {
      SellwildFailures.log(
        code: SellwildFailureCode.listingsItemParse,
        component: SellwildFailureComponent.listings,
        error: firstError,
        message: '$failed result.rs items failed to decode; dropped',
        url: url,
      );
    }

    return SellwildListingsResponse(
      listings: listings,
      config: configMap,
      widgetCacheVersionId: versionId,
    );
  }

  void clearCache() => _cache.clear();

  /// Close the underlying HTTP client. Call when the app is shutting down
  /// or in tests after each test case.
  void dispose() {
    _closed = true;
    _http.close();
  }

  /// Sends one event to the events queue at once. Never throws: a failed
  /// send is counted in [failedEventSends] and not reported, because the
  /// transport never reports itself (FAILURES.md 8.4).
  Future<void> sendEvent({
    required String event,
    String? action,
    String? label,
    // The events uid. Defaults to [uid], the process uid.
    String? uid,
    // Additional free-form passthrough attributes. `platform` + `sdkVersion` are
    // always stamped on top for an installed-base census; caller keys are merged
    // first so the SDK-reserved keys win on collision.
    Map<String, dynamic>? attributes,
    // Analytics kill switch. Defaults on; pass the resolved remote-config
    // EVENTS_ENABLED so events can be stopped via CMS without an app release.
    // [eventsEnabled] (set by configure) must also be on.
    bool enabled = true,
    // Epoch milliseconds. Defaults to now; logFailure passes the time the
    // failure was decided.
    int? createdTime,
  }) async {
    if (!enabled || !eventsEnabled) return;
    const url = 'https://events.sellwild.com/events/queue';
    final code = partnerCode;
    final mergedAttributes = <String, dynamic>{
      // The partner `code` goes first, so a caller's own code (logFailure's
      // cleaned one) wins.
      if (code != null && code.isNotEmpty) 'code': code,
      ...?attributes,
      // `type` is the platform discriminator the events view reads
      // (attributes.type → the `type` column); `sdkVersion` for census.
      'type': 'flutter',
      'sdkVersion': sellwildSdkVersion,
    };
    try {
      final payload = jsonEncode([
        {
          'event': event,
          if (action != null) 'action': action,
          if (label != null) 'label': label,
          'attributes': mergedAttributes,
          'uid': uid ?? this.uid,
          'createdTime': createdTime ?? _clock(),
        }
      ]);
      final response = await _http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      if (response.statusCode < 200 || response.statusCode > 299) {
        _failedEventSends++;
      }
    } catch (_) {
      // Not reported: an events outage would feed failure events back into
      // the endpoint that just failed (FAILURES.md 8.4). Counted instead.
      _failedEventSends++;
    }
  }
}

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

class SellwildException implements Exception {
  final String message;
  SellwildException(this.message);

  @override
  String toString() => 'SellwildException: $message';
}
