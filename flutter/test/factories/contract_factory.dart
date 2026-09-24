// Mock factories for the shapes in sellwild-sdk/contracts/schemas.
//
// A factory starts from a contracts file (a hand-made fixture or a real
// captured sample), never from an inline payload, and applies overrides.
// factories_contract_test.dart validates every variant against
// contracts/schemas/<schema>.schema.json in-process, checks every invalid
// variant fails it for the intended reason, and emits the valid ones to
// contracts/out/flutter for `validate.mjs --out flutter`.

import 'dart:async';

import '../support/fixtures.dart';

/// One named output of a factory. [build] may be async when the payload is
/// captured from SDK code (for example the events client's POST body).
class Variant {
  const Variant(this.name, this.build);

  final String name;
  final FutureOr<Object?> Function() build;
}

/// An invalid output and the ajv error it must produce (as in
/// contracts/fixtures/<shape>/invalid/_expected-errors.json).
class InvalidVariant extends Variant {
  const InvalidVariant(
    super.name,
    super.build, {
    required this.instancePath,
    this.keyword,
  });

  final String instancePath;
  final String? keyword;
}

abstract class ContractFactory {
  /// The schema file name without `.schema.json`.
  String get schema;

  /// Outputs that must match [schema]. The first is the default.
  List<Variant> get variants;

  /// Outputs that must not match [schema].
  List<InvalidVariant> get invalid;
}

/// Marks a key for removal in [JsonObjectFactory.build] overrides (a null
/// value sets JSON null instead).
const Object remove = _Remove();

class _Remove {
  const _Remove();
}

/// A factory whose shape is a JSON object, built from [basePath] (relative
/// to contracts/).
abstract class JsonObjectFactory implements ContractFactory {
  JsonObjectFactory(this.schema, this.basePath);

  @override
  final String schema;

  final String basePath;

  /// A fresh copy of the base file.
  Map<String, dynamic> base() => readContractObject(basePath);

  /// The base with [overrides] applied at the top level.
  Map<String, dynamic> build([Map<String, Object?> overrides = const {}]) {
    final out = base();
    overrides.forEach((key, value) {
      if (identical(value, remove)) {
        out.remove(key);
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}
