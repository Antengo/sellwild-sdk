// JSON Schema (2020-12) validation against contracts/schemas for flutter_test.
//
//   expect(makeEventBatch(), conformsTo('events-batch'));
//
// Uses package:json_schema, which supports 2020-12 `$defs`. A `$ref` to
// another document is answered from the local schemas directory by file name
// (https://contracts.sellwild.com/listing.schema.json -> listing.schema.json).
// Nothing is fetched: an unresolved ref makes compilation throw.
//
// `format` is an assertion here, as it is in contracts/scripts/validate.mjs
// (ajv 8 + ajv-formats), at every depth. json_schema needs two workarounds:
//
// 1. It checks formats only in the validator it was called with, not in the
//    child validators it makes for anyOf, oneOf, allOf, if/then/else, not and
//    contains, so a bad value under those passed. Custom keywords run in
//    every validator, so each schema is compiled under a meta-schema that
//    swaps the 2020-12 format-annotation vocabulary for one whose `format`
//    keyword runs the ajv-formats port in ajv_formats.dart. A format with no
//    port there fails to compile.
// 2. json_schema throws a TypeError when a custom keyword meets a JSON null.
//    So each `format` moves into `if: {type: string}, then: {format}` (inside
//    an allOf when the node already has if/then/else). Formats only constrain
//    strings anyway. validateAgainst turns the resulting "then violated"
//    error back into a format error.
//
// json_schema reports a failed combinator only at the combinator. To check
// that a payload fails for the intended reason, the way validate.mjs checks
// invalid fixtures, use contractErrors: it also lists the errors inside each
// branch, with ajv's instancePath and keyword.
//
// This is a fast in-test check; validate.mjs stays the authority, so factory
// output is also written with emitContract (contract_emitter.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';

import 'ajv_formats.dart';
import 'fixtures.dart';

/// Base URI for schemas without their own `$id`, so relative refs between
/// contract schemas resolve.
const String contractSchemaBase = 'https://contracts.sellwild.com/';

const String _draft2020 = 'https://json-schema.org/draft/2020-12/schema';
const String _metaSchemaUri =
    '${contractSchemaBase}meta/2020-12-ajv-format-assertion';
const String _formatVocabulary =
    '${contractSchemaBase}vocab/ajv-format-assertion';

/// The 2020-12 meta-schema's vocabularies, with format-annotation replaced by
/// [_formatVocabulary]. json_schema only reads `$vocabulary` from it.
const Map<String, dynamic> _metaSchema = {
  r'$schema': _draft2020,
  r'$id': _metaSchemaUri,
  r'$vocabulary': {
    'https://json-schema.org/draft/2020-12/vocab/core': true,
    'https://json-schema.org/draft/2020-12/vocab/applicator': true,
    'https://json-schema.org/draft/2020-12/vocab/unevaluated': true,
    'https://json-schema.org/draft/2020-12/vocab/validation': true,
    'https://json-schema.org/draft/2020-12/vocab/meta-data': true,
    'https://json-schema.org/draft/2020-12/vocab/content': true,
    _formatVocabulary: true,
  },
};

final List<CustomVocabulary> _vocabularies = [
  CustomVocabulary(Uri.parse(_formatVocabulary), {
    'format': CustomKeyword(_formatCheck, _validateFormat),
  }),
];

/// Runs when a schema is compiled: an unknown format throws here, so a schema
/// ajv would check with a format we have not ported cannot pass silently.
Object _formatCheck(JsonSchema schema, Object? format) {
  if (format is! String) {
    throw FormatException('format must be a string: $format');
  }
  final check = ajvFormatChecks[format];
  if (check == null) {
    throw FormatException('format "$format" has no ajv-formats port in '
        'test/support/ajv_formats.dart');
  }
  return (format, check);
}

ValidationContext _validateFormat(
  ValidationContext context,
  Object format,
  Object? instance,
) {
  final (name, check) = format as (String, bool Function(String));
  if (instance is String && !check(instance)) {
    context.addError('"$name" format not accepted $instance');
  }
  return context;
}

// Keywords whose value is a subschema, a map of them, or a list of them.
// Everything else (const, enum, default, examples) is data and left alone.
const Set<String> _schemaKeywords = {
  'additionalProperties',
  'propertyNames',
  'items',
  'contains',
  'not',
  'if',
  'then',
  'else',
  'unevaluatedItems',
  'unevaluatedProperties',
  'contentSchema',
};
const Set<String> _schemaMapKeywords = {
  'properties',
  'patternProperties',
  r'$defs',
  'definitions',
  'dependentSchemas',
};
const Set<String> _schemaListKeywords = {
  'allOf',
  'anyOf',
  'oneOf',
  'prefixItems',
  'items',
};

const String _guardComment =
    'format guard (test/support/contract_schemas.dart)';

/// [node] with every `format` moved behind `if: {type: string}` (workaround 2
/// in the header).
Object? _guardFormats(Object? node) {
  if (node is! Map) return node;
  final out = <String, dynamic>{};
  node.forEach((key, value) {
    if (_schemaListKeywords.contains(key) && value is List) {
      out[key as String] = value.map(_guardFormats).toList();
    } else if (_schemaMapKeywords.contains(key) && value is Map) {
      out[key as String] = value.map((k, v) => MapEntry(k, _guardFormats(v)));
    } else if (_schemaKeywords.contains(key)) {
      out[key as String] = _guardFormats(value);
    } else {
      out[key as String] = value;
    }
  });
  if (!out.containsKey('format')) return out;
  final guard = {
    r'$comment': _guardComment,
    'if': {'type': 'string'},
    'then': {'format': out.remove('format')},
  };
  if (out.keys.any(const {'if', 'then', 'else'}.contains)) {
    out['allOf'] = [...?out['allOf'] as List?, guard];
  } else {
    out.addAll(guard);
  }
  return out;
}

/// A contract schema document ready for json_schema: formats guarded and
/// `$schema` pointing at [_metaSchema]. Contract schemas are 2020-12 only, as
/// in validate.mjs.
Map<String, dynamic> _prepare(Map<String, dynamic> schema, String name) {
  final declared = schema[r'$schema'];
  if (declared != null &&
      declared != _draft2020 &&
      declared != '$_draft2020#') {
    throw FormatException(
        '$name declares \$schema $declared; contract schemas are 2020-12');
  }
  return {
    ...(_guardFormats(schema) as Map<String, dynamic>),
    r'$schema': _metaSchemaUri,
  };
}

/// Compiles [schema] with refs resolved from [schemasDir]
/// (default contracts/schemas).
JsonSchema compileSchema(
  Map<String, dynamic> schema, {
  required String name,
  Directory? schemasDir,
}) {
  final dir = schemasDir ?? Directory(contractsPath('schemas'));
  final compiled = JsonSchema.create(
    _prepare(schema, name),
    schemaVersion: SchemaVersion.draft2020_12,
    fetchedFromUri: Uri.parse('$contractSchemaBase$name.schema.json'),
    refProvider: RefProvider.sync((ref) => _localSchema(ref, dir)),
    customVocabularies: _vocabularies,
  );
  _schemaDirs[compiled] = dir;
  return compiled;
}

// Where each compiled schema's refs came from, for explainErrors.
final Expando<Directory> _schemaDirs = Expando();

/// Returns the local schema a ref names, or null so json_schema reports the
/// ref as unresolved. Also asked for the meta-schema.
Map<String, dynamic>? _localSchema(String ref, Directory dir) {
  if (ref == _metaSchemaUri || ref == '$_metaSchemaUri#') return _metaSchema;
  final segments = Uri.parse(ref).pathSegments;
  if (segments.isEmpty || !segments.last.endsWith('.json')) return null;
  final file = File('${dir.path}/${segments.last}');
  if (!file.existsSync()) return null;
  return _prepare(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      segments.last);
}

// The error json_schema reports when a format guard's `then` fails.
final RegExp _guardError =
    RegExp(r'then violated \((.*), \{format: ([\w-]+)\}\)$', dotAll: true);

/// Validates [instance], `format` included, the way validate.mjs does.
ValidationResults validateAgainst(JsonSchema schema, Object? instance) {
  final results = schema.validate(instance);
  for (final e in results.errors) {
    final m = e.schemaPath.endsWith('/then')
        ? _guardError.firstMatch(e.message)
        : null;
    if (m == null) continue;
    e.message = '"${m[2]}" format not accepted ${m[1]}';
    e.schemaPath =
        '${e.schemaPath.substring(0, e.schemaPath.length - 5)}/format';
  }
  return results;
}

// Keyed by schema file path, so a test that points contractsDirOverride at
// another tree does not get a schema compiled from the real one.
final Map<String, JsonSchema> _compiled = {};

/// contracts/schemas/<name>.schema.json, compiled once per test isolate.
JsonSchema contractSchema(String name) =>
    _compiled[contractsPath('schemas/$name.schema.json')] ??=
        compileSchema(loadSchema(name), name: name);

ValidationResults validateContract(String name, Object? instance) =>
    validateAgainst(contractSchema(name), instance);

/// A schema error as ajv (allErrors) reports it, for checking that a payload
/// fails for the intended reason the way validate.mjs checks invalid fixtures
/// (same instancePath, same keyword).
class ContractError {
  const ContractError(this.instancePath, this.keyword, this.message);

  final String instancePath;

  /// The ajv keyword (`required`, `type`, `anyOf`, `if`, `format`, ...), or
  /// null when json_schema's error has no counterpart listed in [ajvKeyword].
  final String? keyword;

  final String message;

  @override
  String toString() =>
      '${instancePath.isEmpty ? '/' : instancePath} $keyword: $message';
}

/// [contractErrors] for contracts/schemas/<name>.schema.json.
List<ContractError> contractErrors(String name, Object? instance) =>
    explainErrors(contractSchema(name), instance);

/// Every error for [instance] in ajv's shape.
///
/// json_schema reports a failed anyOf, oneOf, allOf or if/then/else only at
/// the combinator, while ajv also lists the errors inside each branch. So each
/// combinator error is followed here by its branches' errors, found by
/// validating the value at that path against each branch. json_schema's
/// second `required` error (at the missing property's own path) is dropped;
/// ajv reports only the one on the object.
List<ContractError> explainErrors(JsonSchema schema, Object? instance) {
  final out = <ContractError>[];
  void visit(JsonSchema node, Object? data, String base, int depth) {
    final errors = validateAgainst(node, data).errors;
    for (var i = 0; i < errors.length; i++) {
      final e = errors[i];
      if (i > 0 && _isRequiredEcho(errors[i - 1], e)) continue;
      final path = '$base${e.instancePath}';
      final keyword = ajvKeyword(e);
      final value = _valueAt(data, e.instancePath);
      // depth 16 means a $ref cycle, which ajv would not get into either.
      final branches = depth == 16 || value == _missing
          ? const <JsonSchema>[]
          : _combinatorBranches(schema, e, keyword, value);
      // An allOf that only wraps a format guard is ours (_guardFormats), not
      // the schema's; ajv reports just the format error under it.
      final failing =
          branches.where((b) => !validateAgainst(b, value).isValid).toList();
      final ours = keyword == 'allOf' &&
          failing.isNotEmpty &&
          failing.every((b) => b.comment == _guardComment);
      if (!ours) out.add(ContractError(path, keyword, e.message));
      for (final branch in failing) {
        visit(branch, value, path, depth + 1);
      }
    }
  }

  visit(schema, instance, '', 0);
  return out;
}

final List<(RegExp, String?)> _messageKeywords = [
  (RegExp(r'^type: wanted '), 'type'),
  (
    RegExp(r'^(const|enum|maxLength|minLength|pattern|maximum|minimum|'
        r'exclusiveMaximum|exclusiveMinimum|multipleOf|maxItems|minItems|'
        r'uniqueItems|minContains|maxContains|contains|minProperties|'
        r'maxProperties)\b'),
    null, // the keyword is the match
  ),
  (RegExp(r'^required prop missing: '), 'required'),
  (RegExp(r'^unallowed additional property '), 'additionalProperties'),
  (RegExp(r'^"[\w-]+" format not accepted '), 'format'),
  (RegExp(r'^additionalItems false'), 'items'),
  (RegExp(r'^unevaluatedItems false'), 'unevaluatedItems'),
  (RegExp(r'^prop .* => .* required'), 'dependentRequired'),
  (RegExp(r'^prop .* violated schema dependency'), 'dependentSchemas'),
  (RegExp(r'^schema is a boolean == false'), 'false schema'),
];

// json_schema starts these messages with the schema path, so they are told
// apart by the keyword that ends the schema path plus the message text.
const Map<String, (String, String)> _combinatorKeywords = {
  'allOf': ('allOf violated', 'allOf'),
  'anyOf': ('anyOf violated', 'anyOf'),
  'oneOf': (': violated', 'oneOf'),
  'not': ('not violated', 'not'),
  'then': ('then violated', 'if'),
  'else': ('else violated', 'if'),
};

/// The ajv keyword for a json_schema error, or null when it is not one of the
/// errors listed above.
String? ajvKeyword(ValidationError error) {
  for (final (pattern, keyword) in _messageKeywords) {
    final m = pattern.firstMatch(error.message);
    if (m != null) return keyword ?? m[1];
  }
  final combinator = _combinatorKeywords[error.schemaPath.split('/').last];
  if (combinator != null && error.message.contains(combinator.$1)) {
    return combinator.$2;
  }
  return null;
}

final RegExp _requiredMessage = RegExp(r'^required prop missing: (.*?) from ');

bool _isRequiredEcho(ValidationError previous, ValidationError e) {
  final m = _requiredMessage.firstMatch(e.message);
  return m != null &&
      previous.message == e.message &&
      e.instancePath == '${previous.instancePath}/${m[1]}';
}

const Object _missing = Object();

/// The value at a json_schema instance path (`/a/0/b`), or [_missing].
Object? _valueAt(Object? data, String path) {
  if (path.isEmpty) return data;
  Object? node = data;
  for (final key in path.substring(1).split('/')) {
    final index = int.tryParse(key);
    if (node is Map && node.containsKey(key)) {
      node = node[key];
    } else if (node is List &&
        index != null &&
        index >= 0 &&
        index < node.length) {
      node = node[index];
    } else {
      return _missing;
    }
  }
  return node;
}

/// The branches of the combinator [error] reports, or none.
///
/// The error's schema path names the node but not always its document, so
/// every loaded contract document is tried. A node counts only if it sits at
/// that path (json_schema's resolvePath falls back to the document root), has
/// that combinator, and fails on [value].
List<JsonSchema> _combinatorBranches(
  JsonSchema root,
  ValidationError error,
  String? keyword,
  Object? value,
) {
  final Iterable<JsonSchema> Function(JsonSchema)? branchesOf =
      switch ((keyword, error.schemaPath.endsWith('/then'))) {
    ('allOf', _) => (n) => n.allOf,
    ('anyOf', _) => (n) => n.anyOf,
    ('oneOf', _) => (n) => n.oneOf,
    ('if', true) => (n) => [n.thenSchema].whereType<JsonSchema>(),
    ('if', false) => (n) => [n.elseSchema].whereType<JsonSchema>(),
    _ => null,
  };
  if (branchesOf == null) return const [];
  final nodePath =
      error.schemaPath.substring(0, error.schemaPath.lastIndexOf('/'));
  final fragment = _fragment(nodePath);
  final documents = nodePath.startsWith('http')
      ? [nodePath.substring(0, nodePath.indexOf('.json') + 5)]
      : [
          '',
          for (final file
              in _schemaDirs[root]?.listSync() ?? const <FileSystemEntity>[])
            if (file.path.endsWith('.schema.json'))
              '$contractSchemaBase${file.uri.pathSegments.last}',
        ];
  final seen = <JsonSchema>{};
  final branches = <JsonSchema>[];
  for (final document in documents) {
    final JsonSchema node;
    try {
      node = root.resolvePath(Uri.parse('$document#$fragment'));
    } on ArgumentError {
      continue; // that document was never loaded by this schema's refs
    } on FormatException {
      continue; // that document has no such path
    }
    if (_fragment(node.path ?? '') != fragment || !seen.add(node)) continue;
    if (branchesOf(node).isEmpty || validateAgainst(node, value).isValid) {
      continue;
    }
    branches.addAll(branchesOf(node));
  }
  return branches;
}

/// The JSON pointer part of a json_schema path, as `/a/b` or '' for a root:
/// '#/$defs/x', '/$defs/x' and 'https://h/x.schema.json//$defs/x' all give
/// '/$defs/x'.
String _fragment(String path) {
  var rest = path;
  final hash = rest.lastIndexOf('#');
  if (hash >= 0) {
    rest = rest.substring(hash + 1);
  } else if (rest.startsWith('http')) {
    rest = rest.substring(rest.indexOf('.json') + 5);
  }
  final segments = rest.split('/').where((s) => s.isNotEmpty);
  return segments.map((s) => '/$s').join();
}

/// Matches a payload that is valid against contracts/schemas/<name>.schema.json.
Matcher conformsTo(String name) => _ConformsToSchema(
    () => contractSchema(name), 'contracts/schemas/$name.schema.json');

/// Matches a payload that is valid against an already compiled [schema].
Matcher conformsToSchema(JsonSchema schema, {String label = 'the schema'}) =>
    _ConformsToSchema(() => schema, label);

class _ConformsToSchema extends Matcher {
  _ConformsToSchema(this._schema, this._label);

  final JsonSchema Function() _schema;
  final String _label;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    final results = validateAgainst(_schema(), item);
    if (!results.isValid) {
      matchState['errors'] = results.errors.map((e) => e.toString()).toList();
    }
    return results.isValid;
  }

  @override
  Description describe(Description description) =>
      description.add('a payload valid against $_label');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    final errors = (matchState['errors'] as List<String>?) ?? const [];
    return mismatchDescription
        .add('has ${errors.length} schema error(s):\n  ')
        .add(errors.take(10).join('\n  '));
  }
}
