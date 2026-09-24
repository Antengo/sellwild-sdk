// The `format` checks of ajv-formats 3 ("full" mode), ported so the Dart
// matcher gives the same answer as contracts/scripts/validate.mjs (ajv 8 +
// ajv-formats) on the formats the contract schemas use.
//
// json_schema's own checks differ: its date-time is DateTime.parse, which
// accepts a bare date ("2026-09-23") that ajv rejects. So contract_schemas.dart
// never uses them: a schema with a format that is not listed here fails to
// compile until the ajv-formats check is ported into this file.
//
// Plain Dart, no Flutter or json_schema import, so a probe script can run it
// next to ajv.

/// Format name -> check, as ajv-formats defines them.
final Map<String, bool Function(String)> ajvFormatChecks = {
  'date': ajvDate,
  'time': ajvTime,
  'date-time': ajvDateTime,
  'uri': ajvUri,
};

final RegExp _date = RegExp(r'^(\d\d\d\d)-(\d\d)-(\d\d)$');
const List<int> _days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

/// RFC 3339 full-date with a real day of the month.
bool ajvDate(String value) {
  final m = _date.firstMatch(value);
  if (m == null) return false;
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  return month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= (month == 2 && _isLeapYear(year) ? 29 : _days[month]);
}

final RegExp _time = RegExp(
  r'^(\d\d):(\d\d):(\d\d(?:\.\d+)?)(z|([+-])(\d\d)(?::?(\d\d))?)?$',
  caseSensitive: false,
);

/// RFC 3339 full-time. The time zone is required (ajv's strictTimeZone), and a
/// leap second is allowed only at 23:59:60 UTC.
bool ajvTime(String value) {
  final m = _time.firstMatch(value);
  if (m == null) return false;
  final hr = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  final sec = double.parse(m[3]!);
  final tz = m[4];
  final tzSign = m[5] == '-' ? -1 : 1;
  final tzH = int.parse(m[6] ?? '0');
  final tzM = int.parse(m[7] ?? '0');
  if (tzH > 23 || tzM > 59 || tz == null) return false;
  if (hr <= 23 && min <= 59 && sec < 60) return true;
  final utcMin = min - tzM * tzSign;
  final utcHr = hr - tzH * tzSign - (utcMin < 0 ? 1 : 0);
  return (utcHr == 23 || utcHr == -1) &&
      (utcMin == 59 || utcMin == -1) &&
      sec < 61;
}

final RegExp _dateTimeSeparator = RegExp(r't|\s', caseSensitive: false);

/// `<date>T<time>` (or a space instead of T), both parts valid.
bool ajvDateTime(String value) {
  final parts = value.split(_dateTimeSeparator);
  return parts.length == 2 && ajvDate(parts[0]) && ajvTime(parts[1]);
}

// Both patterns copied verbatim from ajv-formats 3.0.1 dist/formats.js.
final RegExp _notUriFragment = RegExp(r'\/|:');
final RegExp _uri = RegExp(
  r"^(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\[(?:(?:(?:(?:[0-9a-f]{1,4}:){6}|::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:){0,1}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4})?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4})?::)|[Vv][0-9a-f]+\.[a-z0-9\-._~!$&'()*+,;=:]+)\]|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)|(?:[a-z0-9\-._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\d*)?(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*|\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)(?:\?(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?$",
  caseSensitive: false,
);

/// An absolute URI with a scheme (RFC 3986), as ajv-formats checks it.
bool ajvUri(String value) =>
    _notUriFragment.hasMatch(value) && _uri.hasMatch(value);
