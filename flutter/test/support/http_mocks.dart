// Recording http.Client mocks for flutter_test.
//
// SDK code that takes an injected http.Client (SellwildSDK.configure and
// SellwildAPIClient) gets `recorder.client`; the test then asserts on
// `recorder.requests`. Nothing here opens a socket: MockClient answers
// in-process.
//
// SellwildAPIClient(client: recorder.client) never reaches the production
// events.sellwild.com/events/queue. The shared SellwildAPIClient.instance
// starts on a recording MockClient in every test file
// (test/flutter_test_config.dart), and installNetworkGuard()
// (network_guard.dart) blocks any real dart:io request.
//
//   final recorder = HttpRecorder.json({'CODE': 'weatherbug'});
//   await SellwildSDK.configure(
//       partnerCode: 'weatherbug', slug: 'main', client: recorder.client);
//   expect(recorder.single.url.host, 'widget.sellwild.com');

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef RequestHandler = FutureOr<http.Response> Function(http.Request request);

/// Thrown when a request reaches a handler that has nothing for it
/// (an unrouted host, or more calls than a sequence has answers).
class UnexpectedRequestError extends Error {
  UnexpectedRequestError(this.request, this.reason);

  final http.Request request;
  final String reason;

  @override
  String toString() =>
      'UnexpectedRequestError: ${request.method} ${request.url} ($reason)';
}

/// A MockClient that behaves like IOClient after close(): later requests
/// throw ClientException instead of being answered.
class _TrackingMockClient extends MockClient {
  _TrackingMockClient(HttpRecorder recorder)
      : _recorder = recorder,
        super((request) => recorder._answer(request));

  final HttpRecorder _recorder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_recorder.closeCount > 0) {
      return Future.error(http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      ));
    }
    return super.send(request);
  }

  @override
  void close() {
    _recorder.closeCount++;
    super.close();
  }
}

class HttpRecorder {
  HttpRecorder(this._handler);

  /// Answers every request with [body] JSON-encoded as UTF-8.
  factory HttpRecorder.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) =>
      HttpRecorder((_) => jsonResponse(body, status: status, headers: headers));

  /// Answers every request with a raw [body] (for malformed JSON, HTML error
  /// pages, S3 AccessDenied XML and the like).
  factory HttpRecorder.text(
    String body, {
    int status = 200,
    Map<String, String> headers = const {
      'content-type': 'text/plain; charset=utf-8'
    },
  }) =>
      HttpRecorder((_) => textResponse(body, status: status, headers: headers));

  /// Answers every request with [status] and an empty body.
  factory HttpRecorder.status(int status) =>
      HttpRecorder((_) => textResponse('', status: status));

  /// Fails every request the way a dropped connection does. The default error
  /// is an http.ClientException carrying the request URL.
  factory HttpRecorder.failing([Object? error]) => HttpRecorder((request) {
        throw error ??
            http.ClientException(
                'Connection refused (HttpRecorder)', request.url);
      });

  /// Never answers. Pair with a short timeout, or with fake_async and
  /// `async.elapse(timeout)`, to reach timeout paths.
  factory HttpRecorder.hanging() =>
      HttpRecorder((_) => Completer<http.Response>().future);

  /// Answers call N with handlers[N]. A call past the end throws
  /// [UnexpectedRequestError].
  factory HttpRecorder.sequence(List<RequestHandler> handlers) {
    var next = 0;
    return HttpRecorder((request) {
      if (next >= handlers.length) {
        throw UnexpectedRequestError(
          request,
          'sequence has ${handlers.length} answers, this is call ${next + 1}',
        );
      }
      return handlers[next++](request);
    });
  }

  /// Routes by `url.host`. A host with no route throws
  /// [UnexpectedRequestError], so an unplanned call cannot pass silently.
  factory HttpRecorder.byHost(Map<String, RequestHandler> routes) =>
      HttpRecorder((request) {
        final handler = routes[request.url.host];
        if (handler == null) {
          throw UnexpectedRequestError(
            request,
            'no route for host "${request.url.host}"; routes: ${routes.keys.toList()}',
          );
        }
        return handler(request);
      });

  final RequestHandler _handler;

  /// Every request the client received, in order, including ones whose
  /// handler threw.
  final List<http.Request> requests = [];

  /// Times close() was called on [client].
  int closeCount = 0;

  late final http.Client client = _TrackingMockClient(this);

  bool get closed => closeCount > 0;

  /// The only request. Throws if there were zero or several.
  http.Request get single {
    if (requests.length != 1) {
      throw StateError('Expected exactly 1 request, got ${requests.length}: '
          '${requests.map((r) => '${r.method} ${r.url}').toList()}');
    }
    return requests.single;
  }

  List<Uri> get urls => requests.map((r) => r.url).toList();

  /// Request [index]'s body decoded as JSON.
  Object? jsonBody([int index = 0]) => jsonDecode(requests[index].body);

  Future<http.Response> _answer(http.Request request) async {
    requests.add(request);
    return _handler(request);
  }
}

/// A JSON response encoded as UTF-8, so non-ASCII text survives the trip.
http.Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );

/// A raw text response encoded as UTF-8.
http.Response textResponse(
  String body, {
  int status = 200,
  Map<String, String> headers = const {
    'content-type': 'text/plain; charset=utf-8'
  },
}) =>
    http.Response.bytes(utf8.encode(body), status, headers: headers);
