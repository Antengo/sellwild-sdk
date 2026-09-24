// logFailure shell for Flutter (contracts/FAILURES.md section 3).
//
// Holds the context (partner, flags, injectable clock/uid/sink) and the gate
// state, turns a call into the pure-core input, and hands what decideFailure
// emits to the SDK's existing events client (SellwildAPIClient.sendEvent,
// which sends at once, so `flushNow` needs nothing more here). All decisions
// live in failures_core.dart.
//
// Every failure path in the SDK is a try/catch that calls
// [SellwildFailures.log] with a registry code (sellwild_failure_code.dart).
// log never throws, never awaits and returns void. This file and
// sellwild_log.dart are the only Flutter files allowed to print, and this one
// prints only the debug echo, only when debug is on, through SellwildLog.

import 'dart:async';
import 'dart:io' show HttpException, SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../sellwild_api.dart';
import '../sellwild_config.dart';
import 'failures_core.dart';
import 'sellwild_log.dart';

/// Where emitted events go. The default sends them through
/// [SellwildAPIClient.instance]. A returned future that fails is counted,
/// never reported.
typedef SellwildFailureSink = Future<void> Function(
    ClientFailureEvent event, bool flushNow);

/// What [SellwildFailures.log] reads on every call (FAILURES.md 3.2). Change
/// it with [SellwildFailures.setContext].
class SellwildFailureContext {
  const SellwildFailureContext({
    this.partnerCode,
    this.clientVersion = sellwildSdkVersion,
    this.debug = false,
    this.eventsEnabled,
    this.failuresEnabled,
    this.failuresSampleRate,
    this.wrapper,
    this.clock,
    this.uid,
    this.sink,
  });

  /// Every event from this SDK carries `client: flutter`.
  static const String client = 'flutter';

  /// Set by [SellwildSDK.configure] before its fetch, so config failures
  /// carry the partner.
  final String? partnerCode;
  final String clientVersion;

  /// The SDK debug flag (SellwildConfig.debug): turns on the debug echo and
  /// SellwildLog.
  final bool debug;

  /// EVENTS_ENABLED, FAILURES_ENABLED and FAILURES_SAMPLE_RATE, raw or
  /// coerced; the pure core coerces them. Null means unset: on, rate 1.
  /// configure passes the resolved config, so a host `overrides` callback
  /// that changes SellwildConfig.failuresEnabled wins over the remote value.
  final Object? eventsEnabled;
  final Object? failuresEnabled;
  final Object? failuresSampleRate;

  /// `react-native` or `flutter` when the SDK runs under a wrapper.
  final String? wrapper;

  /// Epoch milliseconds. Null uses the wall clock.
  final int Function()? clock;

  /// The events uid. Null uses [SellwildAPIClient.instance]'s, so sampling
  /// and the wire agree (FAILURES.md 8.3).
  final String Function()? uid;

  /// Null sends through [SellwildAPIClient.instance].
  final SellwildFailureSink? sink;

  FailureContext _toCore() => FailureContext(
        partnerCode: partnerCode,
        client: client,
        clientVersion: clientVersion,
        wrapper: wrapper,
        eventsEnabled: eventsEnabled,
        failuresEnabled: failuresEnabled,
        failuresSampleRate: failuresSampleRate,
      );
}

/// logFailure for Flutter (FAILURES.md 3.4): the thin impure shell around the
/// pure core in failures_core.dart.
abstract final class SellwildFailures {
  // Longest message and error message (UTF-16 units) handed to the pure core.
  // Its sanitizer patterns backtrack quadratically on long runs of letters
  // and digits, and log must never block the UI isolate. Only 200 code points
  // of message are ever sent, so the cut changes nothing but pathological
  // input. Same bound as core/src/failures/index.ts.
  static const int _messageInputMax = 1000;

  static SellwildFailureContext _context = const SellwildFailureContext();
  static FailureState _state = FailureState.initial;
  static bool _inLog = false;
  static int _internalErrors = 0;

  /// The context [log] reads now.
  static SellwildFailureContext get context => _context;

  /// Reports one failure. Call it from the catch (or failure branch) that
  /// handles it, once, at the lowest layer that sees it (FAILURES.md 9).
  ///
  /// [code] is a SellwildFailureCode constant and [component] a
  /// SellwildFailureComponent constant. [severity] is a
  /// SellwildFailureSeverity constant; `error` when null. [error] is the
  /// caught error: its type name and sanitized message are sent. [message] is
  /// a short, PII-free description: never listing text or user data. Only the
  /// host of [url] is sent.
  static void log({
    required String code,
    required String component,
    String? severity,
    Object? error,
    String? message,
    int? httpStatus,
    String? url,
    String? zoneId,
  }) {
    // A nested call from inside log (a sink or printer that reports) returns
    // at once instead of recursing.
    if (_inLog) return;
    _inLog = true;
    try {
      final ctx = _context;
      final input = _toInput(
          code, component, severity, error, message, httpStatus, url, zoneId);
      final decision = decideFailure(
        _state,
        input,
        ctx._toCore(),
        (ctx.uid ?? _queueUid)(),
        (ctx.clock ?? _wallClock)(),
      );
      _state = decision.state;
      final event = decision.event;
      // Send before the echo, so a printer that throws cannot cost the event.
      if (event != null) {
        unawaited((ctx.sink ?? _sendThroughQueue)(event, decision.flushNow)
            .catchError(_countAsyncError));
      }
      if (ctx.debug) SellwildLog.debug(() => echoLine(input, decision.reason));
    } catch (e) {
      _internalError(e);
    } finally {
      _inLog = false;
    }
  }

  /// Updates the context. A null argument keeps the current value;
  /// [resetForTests] clears everything. [debug] also turns SellwildLog on or
  /// off.
  static void setContext({
    String? partnerCode,
    String? clientVersion,
    bool? debug,
    Object? eventsEnabled,
    Object? failuresEnabled,
    Object? failuresSampleRate,
    String? wrapper,
    int Function()? clock,
    String Function()? uid,
    SellwildFailureSink? sink,
  }) {
    final c = _context;
    _context = SellwildFailureContext(
      partnerCode: partnerCode ?? c.partnerCode,
      clientVersion: clientVersion ?? c.clientVersion,
      debug: debug ?? c.debug,
      eventsEnabled: eventsEnabled ?? c.eventsEnabled,
      failuresEnabled: failuresEnabled ?? c.failuresEnabled,
      failuresSampleRate: failuresSampleRate ?? c.failuresSampleRate,
      wrapper: wrapper ?? c.wrapper,
      clock: clock ?? c.clock,
      uid: uid ?? c.uid,
      sink: sink ?? c.sink,
    );
    if (debug != null) SellwildLog.enabled = debug;
  }

  /// Clears the gate state, the internal error count, the whole context and
  /// SellwildLog. Tests only.
  @visibleForTesting
  static void resetForTests() {
    _context = const SellwildFailureContext();
    _state = FailureState.initial;
    _inLog = false;
    _internalErrors = 0;
    SellwildLog.resetForTests();
  }

  /// How many times log itself failed (a throwing clock, uid, sink or error
  /// message getter) since [resetForTests]. Those are counted instead of
  /// reported, since reporting them would recurse (FAILURES.md 3.4).
  @visibleForTesting
  static int get internalErrorCount => _internalErrors;

  /// The gate state after the last call. Tests only.
  @visibleForTesting
  static FailureState get gateState => _state;

  static String _queueUid() => SellwildAPIClient.instance.uid;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  // Sends at once (FAILURES.md 8.1), so flushNow needs nothing more.
  static Future<void> _sendThroughQueue(ClientFailureEvent event, bool _) =>
      SellwildAPIClient.instance.sendEvent(
        event: event.event,
        action: event.action,
        label: event.label,
        uid: event.uid,
        attributes: event.attributes,
        createdTime: event.createdTime,
      );

  // The one catch that does not report (FAILURES.md 3.4): reporting would
  // recurse. Counted for tests and echoed when debug is on.
  static void _internalError(Object error) {
    _internalErrors++;
    try {
      if (_context.debug) {
        SellwildLog.debug(
            () => '[Sellwild] failure internal-error ${error.runtimeType}');
      }
    } catch (_) {
      // The printer itself threw: count it too, and stop there.
      _internalErrors++;
    }
  }

  static void _countAsyncError(Object error) => _internalError(error);

  static FailureInput _toInput(
    String code,
    String component,
    String? severity,
    Object? error,
    String? message,
    int? httpStatus,
    String? url,
    String? zoneId,
  ) {
    String? errName;
    String? errMessage;
    if (error is String) {
      errMessage = error;
    } else if (error != null) {
      errName = error.runtimeType.toString();
      errMessage = _messageOf(error);
    }
    return FailureInput(
      code: code,
      component: component,
      severity: severity,
      errName: errName,
      errMessage: _bounded(errMessage),
      message: _bounded(message),
      httpStatus: httpStatus,
      url: url,
      zoneId: zoneId,
    );
  }

  // FAILURES.md 3.3 (Dart): the exception's message, or toString() when it
  // has none. A throwing toString counts as an internal error and gives no
  // message, so the rest of the report still goes out.
  static String? _messageOf(Object error) {
    try {
      final message = switch (error) {
        FormatException(:final message) => message,
        http.ClientException(:final message) => message,
        TimeoutException(:final message) => message,
        SocketException(:final message) => message,
        HttpException(:final message) => message,
        SellwildException(:final message) => message,
        StateError(:final message) => message,
        _ => null,
      };
      return message == null || message.isEmpty ? error.toString() : message;
    } catch (e) {
      _internalError(e);
      return null;
    }
  }

  static String? _bounded(String? value) =>
      value != null && value.length > _messageInputMax
          ? value.substring(0, _messageInputMax)
          : value;
}
