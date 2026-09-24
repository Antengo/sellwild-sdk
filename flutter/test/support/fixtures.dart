// Shared contract files (sellwild-sdk/contracts) for flutter_test.
//
// `flutter test` runs with the package root (sellwild-sdk/flutter) as its
// working directory, so the contracts live at ../contracts. Set
// SELLWILD_CONTRACTS_DIR to point somewhere else.
//
// Every read decodes the file again, so callers get a fresh mutable copy and
// can change it without leaking into other tests.

import 'dart:convert';
import 'dart:io';

/// Resolves the contracts directory. Pure, so tests can check the rule.
String resolveContractsPath({
  required String cwd,
  Map<String, String> environment = const {},
}) {
  // Directory.uri ends in '/', so resolve() treats cwd as a directory and
  // also collapses the '..'.
  final base = Directory(cwd).absolute.uri;
  final override = environment['SELLWILD_CONTRACTS_DIR'];
  final target = override != null && override.isNotEmpty
      ? base.resolve(override)
      : base.resolve('../contracts');
  final path = target.toFilePath();
  return path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
}

/// Points every loader here at another contracts tree. The support self-tests
/// use it with a temp dir; set it back to null in tearDown.
Directory? contractsDirOverride;

Directory get contractsDir =>
    contractsDirOverride ??
    Directory(resolveContractsPath(
      cwd: Directory.current.path,
      environment: Platform.environment,
    ));

/// Absolute path of [relative] inside the contracts directory.
String contractsPath(String relative) {
  if (relative.startsWith('/') || relative.split('/').contains('..')) {
    throw ArgumentError.value(
        relative, 'relative', 'must stay inside contracts/');
  }
  return '${contractsDir.path}/$relative';
}

/// Decodes a JSON file from the contracts directory.
Object? readContractJson(String relative) {
  final file = File(contractsPath(relative));
  if (!file.existsSync()) {
    throw StateError('Missing contract file ${file.path}. '
        'flutter test must run from sellwild-sdk/flutter, or set SELLWILD_CONTRACTS_DIR.');
  }
  return jsonDecode(file.readAsStringSync());
}

Map<String, dynamic> readContractObject(String relative) {
  final value = readContractJson(relative);
  if (value is! Map<String, dynamic>) {
    throw StateError(
        '$relative is ${value.runtimeType}, expected a JSON object.');
  }
  return value;
}

/// contracts/schemas/<name>.schema.json
Map<String, dynamic> loadSchema(String name) =>
    readContractObject('schemas/$name.schema.json');

/// contracts/fixtures/<shape>/valid|invalid/<name>.json
Object? loadFixture(String shape, String name, {bool valid = true}) =>
    readContractJson(
        'fixtures/$shape/${valid ? 'valid' : 'invalid'}/$name.json');

/// contracts/samples/<shape>/<name>.json (real captured payloads).
Object? loadSample(String shape, String name) =>
    readContractJson('samples/$shape/$name.json');

/// contracts/expectations/<name>.expected.json
Object? loadExpectations(String name) =>
    readContractJson('expectations/$name.expected.json');

/// contracts/golden/log-failure.vectors.json
Object? loadFailureVectors() =>
    readContractJson('golden/log-failure.vectors.json');

/// contracts/failure-codes.json
Object? loadFailureCodes() => readContractJson('failure-codes.json');

/// contracts/fixtures/<shape>/invalid/_expected-errors.json: why each
/// invalid fixture must fail.
Map<String, dynamic> loadExpectedErrors(String shape) =>
    readContractObject('fixtures/$shape/invalid/_expected-errors.json');

/// Names of every contracts/schemas/<name>.schema.json, sorted.
List<String> schemaNames() => _jsonFilesIn('schemas')
    .map(fixtureName)
    .where((name) => name.endsWith('.schema'))
    .map((name) => name.substring(0, name.length - '.schema'.length))
    .toList();

/// Shapes with fixtures (the directories in contracts/fixtures), sorted.
List<String> fixtureShapes() => _dirNamesIn('fixtures');

/// Shapes with captured samples (the directories in contracts/samples), sorted.
List<String> sampleShapes() => _dirNamesIn('samples');

/// Every fixture of one kind, sorted by name so test order is stable.
List<File> fixtureFiles(String shape, {bool valid = true}) =>
    _jsonFilesIn('fixtures/$shape/${valid ? 'valid' : 'invalid'}');

/// Every captured sample for [shape], sorted by name.
List<File> sampleFiles(String shape) => _jsonFilesIn('samples/$shape');

Directory _existingDir(String relative) {
  final dir = Directory(contractsPath(relative));
  if (!dir.existsSync()) {
    throw StateError('Missing contract directory ${dir.path}.');
  }
  return dir;
}

// Skips `_`-prefixed files such as _expected-errors.json, as validate.mjs does.
List<File> _jsonFilesIn(String relative) => _existingDir(relative)
    .listSync()
    .whereType<File>()
    .where((f) =>
        f.path.endsWith('.json') && !f.uri.pathSegments.last.startsWith('_'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

List<String> _dirNamesIn(String relative) => _existingDir(relative)
    .listSync()
    .whereType<Directory>()
    .map((d) => d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
    .toList()
  ..sort();

/// File name without directory or `.json`, for test names.
String fixtureName(File file) {
  final base = file.uri.pathSegments.last;
  return base.endsWith('.json') ? base.substring(0, base.length - 5) : base;
}
