// Writes factory output to contracts/out/flutter/<schema>.<variant>.json so
// `node contracts/scripts/validate.mjs --out flutter` checks it with ajv, the
// same validator every other platform's output goes through.
//
//   emitContract('events-batch', 'failure-default', makeFailureBatch());
//
// SELLWILD_CONTRACT_OUT overrides the base directory (a `flutter/` directory
// is created inside it). validate.mjs and the iOS emitter read the same
// variable; Android takes the `sellwild.contracts.outDir` system property
// instead. A relative value resolves against flutter test's cwd (the package
// root); scripts/coverage/flutter.sh makes it absolute first.

import 'dart:convert';
import 'dart:io';

import 'fixtures.dart';

final RegExp _schemaName = RegExp(r'^[a-z0-9][a-z0-9-]*$');
final RegExp _variantName = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// <contracts>/out/flutter, or $SELLWILD_CONTRACT_OUT/flutter. Pure, so tests
/// can check the rule.
String resolveContractOutPath({
  required String contractsRoot,
  Map<String, String> environment = const {},
}) {
  final override = environment['SELLWILD_CONTRACT_OUT'];
  final base =
      override != null && override.isNotEmpty ? override : '$contractsRoot/out';
  return '$base/flutter';
}

Directory get contractOutDir => Directory(resolveContractOutPath(
      contractsRoot: contractsDir.path,
      environment: Platform.environment,
    ));

/// <out>/flutter-harness, next to [contractOutDir]: where the support
/// self-test's round-trip goes. scripts/coverage/flutter.sh validates it with
/// `--out flutter-harness`, so it proves the emit -> ajv route without ever
/// counting as factory output in `--out flutter`.
Directory get harnessContractOutDir =>
    Directory('${contractOutDir.parent.path}/flutter-harness');

/// Writes [payload] as pretty JSON and returns the file.
///
/// Throws ArgumentError when a name is malformed (a dot in the variant would
/// break the `<schema>.<variant>` split) or when no schema file named
/// [schema] exists in [schemasDir] (default contracts/schemas), so a typo
/// cannot produce a file the validator skips. jsonEncode throws on values
/// that are not JSON.
File emitContract(
  String schema,
  String variant,
  Object? payload, {
  Directory? outDir,
  Directory? schemasDir,
}) {
  if (!_schemaName.hasMatch(schema)) {
    throw ArgumentError.value(
        schema, 'schema', 'must match ${_schemaName.pattern}');
  }
  if (!_variantName.hasMatch(variant)) {
    throw ArgumentError.value(
        variant, 'variant', 'must match ${_variantName.pattern}');
  }
  final schemas = schemasDir ?? Directory(contractsPath('schemas'));
  final schemaFile = File('${schemas.path}/$schema.schema.json');
  if (!schemaFile.existsSync()) {
    throw ArgumentError.value(schema, 'schema', 'no ${schemaFile.path}');
  }
  final text = '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  final dir = outDir ?? contractOutDir;
  dir.createSync(recursive: true);
  final file = File('${dir.path}/$schema.$variant.json');
  file.writeAsStringSync(text);
  return file;
}
