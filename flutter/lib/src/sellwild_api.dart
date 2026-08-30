import 'dart:convert';
import 'package:http/http.dart' as http;
import 'sellwild_config.dart';
import 'sellwild_models.dart';

/// Sellwild API client for fetching listings and sending analytics.
class SellwildAPIClient {
  static final SellwildAPIClient instance = SellwildAPIClient._();
  SellwildAPIClient._();

  final _cache = <String, SellwildListingsResponse>{};
  final _http = http.Client();

  Future<SellwildListingsResponse> fetchListings(SellwildConfig config) async {
    final url = config.effectiveListingsUrl;
    if (_cache.containsKey(url)) return _cache[url]!;

    final response = await _http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw SellwildException('HTTP ${response.statusCode} from $url');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = (data['result'] as Map<String, dynamic>?) ?? data;
    final rs = (result['rs'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final configMap = (result['config'] as Map<String, dynamic>?) ?? {};
    final versionId = result['widgetCacheVersionId'] as String?;

    final listings = rs.map(SellwildListing.fromJson).toList();
    final res = SellwildListingsResponse(
      listings: listings,
      config: configMap,
      widgetCacheVersionId: versionId,
    );
    _cache[url] = res;
    return res;
  }

  void clearCache() => _cache.clear();

  /// Close the underlying HTTP client. Call when the app is shutting down
  /// or in tests after each test case.
  void dispose() => _http.close();

  Future<void> sendEvent({
    required String event,
    String? action,
    String? label,
    required String uid,
    // Additional free-form passthrough attributes. `platform` + `sdkVersion` are
    // always stamped on top for an installed-base census; caller keys are merged
    // first so the SDK-reserved keys win on collision.
    Map<String, dynamic>? attributes,
    // Analytics kill switch. Defaults on; pass the resolved remote-config
    // EVENTS_ENABLED so events can be stopped via CMS without an app release.
    bool enabled = true,
  }) async {
    if (!enabled) return;
    const url = 'https://events.sellwild.com/events/queue';
    final mergedAttributes = <String, dynamic>{
      ...?attributes,
      'platform': 'flutter',
      'sdkVersion': sellwildSdkVersion,
    };
    final payload = jsonEncode([
      {
        'event': event,
        if (action != null) 'action': action,
        if (label != null) 'label': label,
        'attributes': mergedAttributes,
        'uid': uid,
        'createdTime': DateTime.now().millisecondsSinceEpoch,
      }
    ]);
    await _http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );
  }
}

class SellwildException implements Exception {
  final String message;
  SellwildException(this.message);

  @override
  String toString() => 'SellwildException: $message';
}
