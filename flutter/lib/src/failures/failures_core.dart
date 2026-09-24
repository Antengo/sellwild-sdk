// Pure core of logFailure (contracts/FAILURES.md sections 5-7): a port of
// contracts/reference/log-failure.mjs.
//
// Everything here is deterministic and free of side effects: the shell
// (sellwild_failures.dart) reads the context, uid and clock, calls
// [decideFailure] and pushes what it returns. The core must reproduce
// contracts/golden/log-failure.vectors.json and log-failure.utf16.vectors.json
// exactly (test/failures/failures_core_golden_test.dart).
//
// Units: string lengths are Unicode code points (Dart `runes`, which keep a
// lone surrogate as one unit, like the reference), sizes are UTF-8 bytes,
// times are epoch milliseconds. Inputs are `Object?` because the vectors feed
// wrong JSON types on purpose; missing and null are the same everywhere.
//
// Dart's RegExp has JavaScript semantics, so the sanitizer patterns below are
// the reference's patterns unchanged (no flags, UTF-16 code units).

import 'dart:convert';

const String failureContractVersion = '1';
const String failureEventName = 'clientFailure';
const String invalidFailureCode = 'client.code.invalid';
const String _unknown = 'unknown';

/// Allowed `label` values (FAILURES.md 6.2).
const List<String> failureComponents = [
  'configure',
  'remoteConfig',
  'listings',
  'localized',
  'feed',
  'banner',
  'native',
  'video',
  'house',
  'bridge',
  'webview',
  'widget',
  'shorts',
  'tv',
  'flipcard',
  'growthcode',
  'geo',
  'storage',
];

const List<String> failureSeverities = ['fatal', 'error', 'warn'];

const List<String> _wrappers = ['react-native', 'flutter'];

/// Wire order of attribute keys. This is also the allowlist: nothing else is
/// sent.
const List<String> failureAttributeKeys = [
  'code',
  'client',
  'clientVersion',
  'severity',
  'fv',
  'errName',
  'msg',
  'stack',
  'httpStatus',
  'host',
  'zoneId',
  'wrapper',
  'release',
  'seq',
  'repeat',
  'capped',
];

/// The limits in contracts/golden/log-failure.vectors.json `limits`.
abstract final class FailureLimits {
  static const int codeMax = 64;
  static const int errName = 64;
  static const int msg = 200;
  static const int msgBudget = 80;
  static const int msgKey = 64;
  static const int stack = 800;
  static const int stackFrames = 5;
  static const int zoneId = 32;
  static const int host = 253;
  static const int partnerCode = 64;
  static const int clientVersion = 32;
  static const int release = 64;
  static const int eventBytes = 2048;
  static const int dedupeWindowMs = 60000;
  static const int lruSize = 50;
  static const int perKeyEmits = 3;
  static const int sessionEmits = 20;
}

const int _ellipsis = 0x2026;
const int _zwj = 0x200d;
const int _maxSafeInteger = 9007199254740991;

final RegExp _codeRe =
    RegExp(r'^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$');
final RegExp _codeCharsRe = RegExp(r'^[a-z0-9_.]+$');
final RegExp _schemeRe = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*$');
final RegExp _ipv4Re =
    RegExp(r'^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$');
final RegExp _httpStatusRe = RegExp(r'^[0-9]{3}$');
final RegExp _rateRe = RegExp(r'^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$');
final RegExp _queryOrFragment = RegExp(r'[?#]');

// ── Code points ─────────────────────────────────────────────────────────────

bool _isLoneSurrogate(int cp) => cp >= 0xd800 && cp <= 0xdfff;

// Code points that attach to the one before them. A cut never separates them
// from their base: the base is dropped with them.
bool _isExtender(int cp) =>
    (cp >= 0x0300 && cp <= 0x036f) ||
    (cp >= 0x1ab0 && cp <= 0x1aff) ||
    (cp >= 0x1dc0 && cp <= 0x1dff) ||
    (cp >= 0x20d0 && cp <= 0x20ff) ||
    (cp >= 0xfe00 && cp <= 0xfe0f) ||
    (cp >= 0xfe20 && cp <= 0xfe2f) ||
    cp == _zwj ||
    (cp >= 0x1f3fb && cp <= 0x1f3ff) ||
    (cp >= 0xe0020 && cp <= 0xe007f) ||
    (cp >= 0xe0100 && cp <= 0xe01ef);

bool _isRegionalIndicator(int cp) => cp >= 0x1f1e6 && cp <= 0x1f1ff;

/// Cut [s] to at most [max] code points. When a cut happens the result ends
/// in "…", which counts toward [max]. Never splits a surrogate pair, never
/// leaves a combining mark, variation selector, skin tone, tag or ZWJ without
/// its base, and never splits a regional-indicator (flag) pair.
String truncateUnicode(String s, int max) {
  final cps = s.runes.toList();
  if (cps.length <= max) return s;
  var k = max - 1;
  while (k > 0 && (_isExtender(cps[k]) || cps[k - 1] == _zwj)) {
    k--;
  }
  if (k > 0 && _isRegionalIndicator(cps[k])) {
    var run = 0;
    for (var i = k - 1; i >= 0 && _isRegionalIndicator(cps[i]); i--) {
      run++;
    }
    if (run.isOdd) k--;
  }
  return String.fromCharCodes([...cps.take(k), _ellipsis]);
}

String _firstCodePoints(String s, int n) {
  final cps = s.runes.toList();
  return cps.length <= n ? s : String.fromCharCodes(cps.take(n));
}

// ── Text cleanup ────────────────────────────────────────────────────────────

// Space-like code points that become U+0020 before collapsing.
bool _isSpaceLike(int cp) =>
    cp <= 0x1f ||
    (cp >= 0x7f && cp <= 0x9f) ||
    cp == 0x20 ||
    cp == 0xa0 ||
    cp == 0x1680 ||
    (cp >= 0x2000 && cp <= 0x200a) ||
    cp == 0x2028 ||
    cp == 0x2029 ||
    cp == 0x202f ||
    cp == 0x205f ||
    cp == 0x3000 ||
    cp == 0xfeff;

/// Lone surrogates become U+FFFD, control and space-like code points become
/// one space, runs of spaces collapse, and the ends are trimmed. Anything
/// that is not a String gives ''.
String cleanText(Object? s) {
  if (s is! String) return '';
  final out = StringBuffer();
  var pendingSpace = false;
  for (final cp in s.runes) {
    if (_isSpaceLike(cp)) {
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) out.writeCharCode(0x20);
    pendingSpace = false;
    out.writeCharCode(_isLoneSurrogate(cp) ? 0xfffd : cp);
  }
  return out.toString();
}

String _asciiLower(String s) => String.fromCharCodes(
    s.codeUnits.map((c) => c >= 0x41 && c <= 0x5a ? c + 0x20 : c));

bool _isAsciiSpace(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0d);

/// Trim U+0009-U+000D and U+0020 only (identical on every platform).
String trimAscii(String s) {
  var a = 0;
  var b = s.length;
  while (a < b && _isAsciiSpace(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && _isAsciiSpace(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

// ── Host extraction ─────────────────────────────────────────────────────────

const String _hostPunctuation = ".-_~%!\$&'*+,;=:@[]";

bool _isAuthorityChar(int cp) =>
    cp >= 0x80 ||
    (cp >= 0x61 && cp <= 0x7a) ||
    (cp >= 0x41 && cp <= 0x5a) ||
    (cp >= 0x30 && cp <= 0x39) ||
    _hostPunctuation.codeUnits.contains(cp);

/// Hostname of an absolute (`scheme://`) or protocol-relative (`//`) URL,
/// lower case, without userinfo, port or trailing dots. IP literals become
/// "<ip>". Returns null when there is no host.
String? hostOf(Object? url) {
  if (url is! String) return null;
  final s = trimAscii(url);
  final String rest;
  final i = s.indexOf('://');
  if (i > 0 && _schemeRe.hasMatch(s.substring(0, i))) {
    rest = s.substring(i + 3);
  } else if (s.startsWith('//')) {
    rest = s.substring(2);
  } else {
    return null;
  }
  final authority = StringBuffer();
  for (final cp in rest.runes) {
    if (cp == 0x2f || cp == 0x3f || cp == 0x23 || !_isAuthorityChar(cp)) break;
    authority.writeCharCode(cp);
  }
  var auth = authority.toString();
  final at = auth.lastIndexOf('@');
  if (at >= 0) auth = auth.substring(at + 1);
  if (auth.startsWith('[')) return auth.contains(']') ? '<ip>' : null;
  final colon = auth.indexOf(':');
  if (colon >= 0) auth = auth.substring(0, colon);
  while (auth.endsWith('.')) {
    auth = auth.substring(0, auth.length - 1);
  }
  final host = _asciiLower(auth);
  if (host.isEmpty) return null;
  if (_ipv4Re.hasMatch(host)) return '<ip>';
  return host;
}

// ── Message and stack sanitizing ────────────────────────────────────────────

// One left-to-right pass; the first alternative that matches at a position
// wins and replaced text is never scanned again.
const String _urlAlt = r'''([A-Za-z][A-Za-z0-9+.-]*://[^ "'<>()]*)''';
const String _protoRelAlt = r'''(//[A-Za-z0-9-]+\.[^ "'<>()]*)''';
const String _emailAlt = r'([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})';
const String _uuidAlt =
    r'([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})';
const String _ipv4Alt = r'([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})';
const String _digitsAlt = r'([0-9]{6,})';
const String _pathAlt = r'([^ ():]*/)';
const String _queryAlt = r'(\?[^ :()]*)';

final RegExp _messageRe = RegExp([
  _urlAlt,
  _protoRelAlt,
  _emailAlt,
  _uuidAlt,
  _ipv4Alt,
  _digitsAlt
].join('|'));
final RegExp _frameRe = RegExp([
  _urlAlt,
  _protoRelAlt,
  _emailAlt,
  _uuidAlt,
  _ipv4Alt,
  _pathAlt,
  _queryAlt
].join('|'));

/// PII-safe message: [cleanText], then URLs become their host (or "<url>"),
/// emails "<email>", UUIDs "<id>", IPv4 "<ip>" and 6+ digit runs "<n>". Not
/// truncated here.
String sanitizeMessage(Object? s) =>
    cleanText(s).replaceAllMapped(_messageRe, (m) {
      if (m[1] != null || m[2] != null) return hostOf(m[0]) ?? '<url>';
      if (m[3] != null) return '<email>';
      if (m[4] != null) return '<id>';
      if (m[5] != null) return '<ip>';
      return '<n>';
    });

String _basenameOfUrl(String u) {
  final cut = u.indexOf(_queryOrFragment);
  final path = cut >= 0 ? u.substring(0, cut) : u;
  return path.substring(path.lastIndexOf('/') + 1);
}

String _sanitizeFrame(String line) =>
    cleanText(line).replaceAllMapped(_frameRe, (m) {
      if (m[1] != null || m[2] != null) {
        final host = hostOf(m[0]);
        if (host != null) return host;
        final base = _basenameOfUrl(m[0]!);
        return base.isEmpty ? '<url>' : base;
      }
      if (m[3] != null) return '<email>';
      if (m[4] != null) return '<id>';
      if (m[5] != null) return '<ip>';
      return '';
    });

/// First 5 frames of a stack, one per line: the engine header line
/// ([errName] or `errName: …`) is dropped, URLs become hosts, directories
/// and query strings are removed, emails/UUIDs/IPs are masked. At most 800
/// code points. Null when nothing is left.
String? sanitizeStack(Object? stack, String? errName) {
  if (stack is! String) return null;
  var lines = stack
      .split('\n')
      .map((l) => trimAscii(l.replaceAll('\r', '')))
      .where((l) => l.isNotEmpty)
      .toList();
  if (errName != null &&
      errName.isNotEmpty &&
      lines.isNotEmpty &&
      (lines.first == errName || lines.first.startsWith('$errName:'))) {
    lines = lines.sublist(1);
  }
  final frames = lines
      .take(FailureLimits.stackFrames)
      .map(_sanitizeFrame)
      .where((l) => l.isNotEmpty)
      .toList();
  if (frames.isEmpty) return null;
  return truncateUnicode(frames.join('\n'), FailureLimits.stack);
}

// ── Field normalizers ───────────────────────────────────────────────────────

/// A code that fails the registry format becomes "client.code.invalid".
String normalizeCode(Object? code) {
  if (code is! String || code.length > FailureLimits.codeMax) {
    return invalidFailureCode;
  }
  if (!_codeCharsRe.hasMatch(code) || !_codeRe.hasMatch(code)) {
    return invalidFailureCode;
  }
  return code;
}

/// Exact match against the component list, else "unknown".
String normalizeComponent(Object? component) =>
    component is String && failureComponents.contains(component)
        ? component
        : _unknown;

/// Exact match against fatal | error | warn, else "error".
String normalizeSeverity(Object? severity) =>
    severity is String && failureSeverities.contains(severity)
        ? severity
        : 'error';

// A JSON number as the reference sees it: an int, or a double with no
// fraction (JSON `503.0` is the integer 503 in JavaScript). Null otherwise.
int? _wholeNumber(Object? v, {required num min, required num max}) {
  if (v is int) return v >= min && v <= max ? v : null;
  if (v is double && v.isFinite && v == v.truncateToDouble()) {
    return v >= min && v <= max ? v.toInt() : null;
  }
  return null;
}

/// HTTP status as exactly three digits, else null.
String? normalizeHttpStatus(Object? v) {
  if (v is num) return _wholeNumber(v, min: 100, max: 999)?.toString();
  if (v is String) {
    final t = trimAscii(v);
    return _httpStatusRe.hasMatch(t) ? t : null;
  }
  return null;
}

/// Safe integers or strings; cleaned and cut to 32 code points.
String? normalizeZoneId(Object? v) {
  final String? s;
  if (v is num) {
    s = _wholeNumber(v, min: -_maxSafeInteger, max: _maxSafeInteger)
        ?.toString();
  } else if (v is String) {
    s = v;
  } else {
    s = null;
  }
  if (s == null) return null;
  final t = cleanText(s);
  return t.isEmpty ? null : truncateUnicode(t, FailureLimits.zoneId);
}

String? _cleanBounded(Object? v, int max) {
  if (v is! String) return null;
  final t = cleanText(v);
  return t.isEmpty ? null : truncateUnicode(t, max);
}

// ── Flags and sampling ──────────────────────────────────────────────────────

const List<String> _falseWords = ['false', '0', 'no', 'off'];

/// Kill-switch coercion (FAILURES.md 5.3): a bool as is; a number is on when
/// it is not 0; a string is on unless it is false/0/no/off after ASCII trim
/// and ASCII lower case; anything else (null, absent, map, list) is [dflt].
bool coerceFlag(Object? v, [bool dflt = true]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return !_falseWords.contains(_asciiLower(trimAscii(v)));
  return dflt;
}

/// FAILURES_SAMPLE_RATE (FAILURES.md 5.4): a finite number, or a plain
/// decimal string, clamped to [0, 1]. Anything else (null, '', NaN, '50%',
/// booleans, maps) is 1.
double coerceRate(Object? v) {
  double? n;
  if (v is num) {
    n = v.isFinite ? v.toDouble() : null;
  } else if (v is String) {
    final t = trimAscii(v);
    if (_rateRe.hasMatch(t)) n = double.parse(t);
  }
  if (n == null) return 1;
  return n < 0 ? 0 : (n > 1 ? 1 : n);
}

/// FNV-1a 32-bit over the UTF-8 bytes of [s] (lone surrogates as U+FFFD), as
/// an unsigned integer. Anything that is not a String hashes as ''.
int fnv1a32(Object? s) {
  final bytes = utf8.encode(s is String ? _replaceLoneSurrogates(s) : '');
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    // h * 0x01000193 mod 2^32, split so no step needs more than 53 bits.
    h = (((h & 0xff) << 24) + h * 0x193) & 0xffffffff;
  }
  return h;
}

String _replaceLoneSurrogates(String s) => String.fromCharCodes(
    s.runes.map((cp) => _isLoneSurrogate(cp) ? 0xfffd : cp));

/// Session sampling: fnv1a32(uid + ":failures") / 2^32 < rate. A uid that is
/// not a String counts as ''.
bool isSampled(Object? uid, double rate) {
  if (rate >= 1) return true;
  if (rate <= 0) return false;
  final u = uid is String ? uid : '';
  return fnv1a32('$u:failures') / 4294967296 < rate;
}

// ── State ───────────────────────────────────────────────────────────────────

/// One dedupe key's bookkeeping (FAILURES.md 5.1).
class FailureKeyEntry {
  const FailureKeyEntry({
    required this.key,
    required this.lastEmitAt,
    required this.suppressed,
    required this.emits,
  });

  final String key;
  final int lastEmitAt;
  final int suppressed;
  final int emits;
}

/// The gate state for one session. [keys] run from least to most recently
/// used.
class FailureState {
  const FailureState({this.sessionCount = 0, this.keys = const []});

  static const FailureState initial = FailureState();

  final int sessionCount;
  final List<FailureKeyEntry> keys;
}

/// `action|label|errName|first 64 code points of the sanitized (uncut)
/// message`.
String dedupeKey(
        String action, String label, String? errName, String msgFull) =>
    [
      action,
      label,
      errName ?? '',
      _firstCodePoints(msgFull, FailureLimits.msgKey),
    ].join('|');

List<FailureKeyEntry> _touch(
        List<FailureKeyEntry> keys, FailureKeyEntry entry) =>
    [...keys.where((e) => e.key != entry.key), entry];

// ── Input, context, event ───────────────────────────────────────────────────

/// What a call site reported, already turned into the core's fields by the
/// shell (FAILURES.md 3.3). Every field may hold any JSON value; the core
/// normalizes it.
class FailureInput {
  const FailureInput({
    this.code,
    this.component,
    this.severity,
    this.errName,
    this.errMessage,
    this.message,
    this.stack,
    this.httpStatus,
    this.url,
    this.zoneId,
  });

  final Object? code;
  final Object? component;
  final Object? severity;
  final Object? errName;
  final Object? errMessage;
  final Object? message;
  final Object? stack;
  final Object? httpStatus;
  final Object? url;
  final Object? zoneId;
}

/// The context fields the core reads (FAILURES.md 3.2). The flags are the raw
/// remote values; null means unset, which means on and rate 1.
class FailureContext {
  const FailureContext({
    this.partnerCode,
    this.client,
    this.clientVersion,
    this.wrapper,
    this.release,
    this.eventsEnabled,
    this.failuresEnabled,
    this.failuresSampleRate,
  });

  final Object? partnerCode;
  final Object? client;
  final Object? clientVersion;
  final Object? wrapper;
  final Object? release;
  final Object? eventsEnabled;
  final Object? failuresEnabled;
  final Object? failuresSampleRate;
}

/// One clientFailure event (FAILURES.md 6). [attributes] is in wire order.
class ClientFailureEvent {
  const ClientFailureEvent({
    required this.action,
    required this.label,
    required this.attributes,
    required this.uid,
    required this.createdTime,
  });

  String get event => failureEventName;
  final String action;
  final String label;
  final Map<String, String> attributes;
  final String uid;
  final int createdTime;

  Map<String, Object> toJson() => {
        'event': event,
        'action': action,
        'label': label,
        'attributes': {...attributes},
        'uid': uid,
        'createdTime': createdTime,
      };
}

/// What [decideFailure] returns. [event] is null when the call was dropped,
/// and [reason] then names the gate that dropped it.
class FailureDecision {
  const FailureDecision({
    required this.state,
    required this.event,
    required this.flushNow,
    required this.reason,
  });

  final FailureState state;
  final ClientFailureEvent? event;
  final bool flushNow;
  final String? reason;
}

// ── Event building ──────────────────────────────────────────────────────────

String _jsonString(String s) {
  final out = StringBuffer('"');
  for (final cp in s.runes) {
    switch (cp) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (cp < 0x20) {
          out.write('\\u${cp.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(cp);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// Canonical JSON of [event] (fixed key order, no whitespace, minimal
/// escaping, "/" and non-ASCII left literal). Its UTF-8 length is what the
/// 2048-byte budget measures; the platform encoder is not used for it.
String canonicalJson(ClientFailureEvent event) {
  final attributes = failureAttributeKeys
      .where(event.attributes.containsKey)
      .map((k) => '${_jsonString(k)}:${_jsonString(event.attributes[k]!)}')
      .join(',');
  return '{"event":${_jsonString(event.event)}'
      ',"action":${_jsonString(event.action)}'
      ',"label":${_jsonString(event.label)}'
      ',"attributes":{$attributes}'
      ',"uid":${_jsonString(event.uid)}'
      ',"createdTime":${event.createdTime}}';
}

int eventByteSize(ClientFailureEvent event) =>
    utf8.encode(canonicalJson(event)).length;

ClientFailureEvent _buildEvent({
  required String action,
  required String label,
  required String severity,
  required String? errName,
  required String? msg,
  required String? stack,
  required String? httpStatus,
  required String? host,
  required String? zoneId,
  required int seq,
  required int repeat,
  required FailureContext context,
  required Object? uid,
  required int now,
}) {
  final client = context.client;
  final wrapper = context.wrapper;
  final candidates = <String, String?>{
    'code': _cleanBounded(context.partnerCode, FailureLimits.partnerCode) ??
        _unknown,
    'client': client is String && client.isNotEmpty ? client : _unknown,
    'clientVersion':
        _cleanBounded(context.clientVersion, FailureLimits.clientVersion) ??
            _unknown,
    'severity': severity,
    'fv': failureContractVersion,
    'errName': errName,
    'msg': msg,
    'stack': stack,
    'httpStatus': httpStatus,
    'host': host,
    'zoneId': zoneId,
    'wrapper': _wrappers.contains(wrapper) ? wrapper as String : null,
    'release': _cleanBounded(context.release, FailureLimits.release),
    'seq': '$seq',
    'repeat': '$repeat',
    'capped': seq == FailureLimits.sessionEmits ? '1' : null,
  };
  final attributes = <String, String>{
    for (final k in failureAttributeKeys)
      if (candidates[k] != null) k: candidates[k]!,
  };
  final event = ClientFailureEvent(
    action: action,
    label: label,
    attributes: attributes,
    uid: uid is String ? uid : '',
    createdTime: now,
  );
  // The size budget (FAILURES.md 6.4): drop the stack, then cut the message
  // to 80, then drop it; still over is sent as is.
  bool over() => eventByteSize(event) > FailureLimits.eventBytes;
  if (over()) attributes.remove('stack');
  final cut = attributes['msg'];
  if (over() && cut != null) {
    attributes['msg'] = truncateUnicode(cut, FailureLimits.msgBudget);
  }
  if (over()) attributes.remove('msg');
  return event;
}

// ── The gate ────────────────────────────────────────────────────────────────

/// The full sanitized message (FAILURES.md 7.5): the message and the error
/// message joined with ": ", the error left out when it equals the message.
String messageFull(FailureInput input) {
  final fromMessage = sanitizeMessage(input.message);
  final fromError = sanitizeMessage(input.errMessage);
  return [
    fromMessage,
    if (fromError != fromMessage) fromError,
  ].where((p) => p.isNotEmpty).join(': ');
}

/// The whole decision as a pure function (FAILURES.md 5.2).
FailureDecision decideFailure(
  FailureState state,
  FailureInput input,
  FailureContext context,
  Object? uid,
  int now,
) {
  FailureDecision drop(String reason, [FailureState? next]) => FailureDecision(
      state: next ?? state, event: null, flushNow: false, reason: reason);

  if (!coerceFlag(context.eventsEnabled)) return drop('events_disabled');
  if (!coerceFlag(context.failuresEnabled)) return drop('failures_disabled');

  final action = normalizeCode(input.code);
  final label = normalizeComponent(input.component);
  final severity = normalizeSeverity(input.severity);

  if (severity != 'fatal' &&
      !isSampled(uid, coerceRate(context.failuresSampleRate))) {
    return drop('sampled_out');
  }
  if (state.sessionCount >= FailureLimits.sessionEmits) {
    return drop('session_capped');
  }

  final errName = _cleanBounded(input.errName, FailureLimits.errName);
  final msgFull = messageFull(input);
  final key = dedupeKey(action, label, errName, msgFull);
  final existing = state.keys.where((e) => e.key == key).firstOrNull;
  if (existing != null) {
    if (existing.emits >= FailureLimits.perKeyEmits) {
      return drop('key_capped', _withKeys(state, _touch(state.keys, existing)));
    }
    if (now - existing.lastEmitAt < FailureLimits.dedupeWindowMs) {
      final bumped = FailureKeyEntry(
        key: key,
        lastEmitAt: existing.lastEmitAt,
        suppressed: existing.suppressed + 1,
        emits: existing.emits,
      );
      return drop('deduped', _withKeys(state, _touch(state.keys, bumped)));
    }
  }

  final seq = state.sessionCount + 1;
  final entry = FailureKeyEntry(
    key: key,
    lastEmitAt: now,
    suppressed: 0,
    emits: (existing?.emits ?? 0) + 1,
  );
  var keys = _touch(state.keys, entry);
  if (keys.length > FailureLimits.lruSize) {
    keys = keys.sublist(keys.length - FailureLimits.lruSize);
  }

  final host = hostOf(input.url);
  final event = _buildEvent(
    action: action,
    label: label,
    severity: severity,
    errName: errName,
    msg: msgFull.isEmpty ? null : truncateUnicode(msgFull, FailureLimits.msg),
    stack: sanitizeStack(input.stack, errName),
    httpStatus: normalizeHttpStatus(input.httpStatus),
    host: host == null ? null : truncateUnicode(host, FailureLimits.host),
    zoneId: normalizeZoneId(input.zoneId),
    seq: seq,
    repeat: (existing?.suppressed ?? 0) + 1,
    context: context,
    uid: uid,
    now: now,
  );

  return FailureDecision(
    state: FailureState(sessionCount: seq, keys: keys),
    event: event,
    flushNow: seq == 1 || severity == 'fatal',
    reason: null,
  );
}

FailureState _withKeys(FailureState state, List<FailureKeyEntry> keys) =>
    FailureState(sessionCount: state.sessionCount, keys: keys);

/// The debug echo line (FAILURES.md 2):
/// `[Sellwild] failure <action> <label> <severity> <reason or "sent"> <msg>`,
/// with the sanitized message only.
String echoLine(FailureInput input, String? reason) {
  final msg = truncateUnicode(messageFull(input), FailureLimits.msg);
  return [
    '[Sellwild] failure',
    normalizeCode(input.code),
    normalizeComponent(input.component),
    normalizeSeverity(input.severity),
    reason ?? 'sent',
    if (msg.isNotEmpty) msg,
  ].join(' ');
}
