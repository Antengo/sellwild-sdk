import Foundation

/// Writes values produced by iOS code (factory output, wire events, request
/// bodies) as JSON for `node contracts/scripts/validate.mjs --out ios`, which
/// checks each file against `contracts/schemas/<schema>.schema.json`.
///
///     try ContractEmitter.emit(eventDict, schema: "events-batch", variant: "client-failure")
///
/// writes `contracts/out/ios/events-batch.client-failure.json`. With
/// `SELLWILD_CONTRACT_OUT` set, files go to `$SELLWILD_CONTRACT_OUT/ios/`
/// instead, matching the Android and Flutter emitters. Tests run in the
/// simulator, so `scripts/coverage/ios.sh` forwards the variable as
/// `TEST_RUNNER_SELLWILD_CONTRACT_OUT`.
///
/// Swift gets no schema library on purpose: a Package.swift dependency, even
/// a test-only one, enters partners' SPM resolution.
enum ContractEmitter {

    enum Failure: Error, CustomStringConvertible, Equatable {
        case badSchemaName(String)
        case badVariantName(String)
        case unknownSchema(String, URL)
        case notJSON(String)

        var description: String {
            switch self {
            case .badSchemaName(let name):
                return "Contract schema name \"\(name)\" must match [a-z0-9][a-z0-9-]*"
            case .badVariantName(let name):
                return "Contract variant name \"\(name)\" must match [A-Za-z0-9][A-Za-z0-9_-]*"
            case .unknownSchema(let name, let file):
                return "No schema \"\(name)\": \(file.path) does not exist, so the validator would skip this output"
            case .notJSON(let reason):
                return "Contract output is not valid JSON: \(reason)"
            }
        }
    }

    static let environmentKey = "SELLWILD_CONTRACT_OUT"
    static let platform = "ios"
    static let schemasDirectory = Fixtures.contractsDirectory.appendingPathComponent("schemas", isDirectory: true)

    /// `$SELLWILD_CONTRACT_OUT/ios` when the variable is set and not empty,
    /// else `contracts/out/ios` in this repo.
    static func outputDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base: URL
        if let override = environment[environmentKey], !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = Fixtures.contractsDirectory.appendingPathComponent("out", isDirectory: true)
        }
        return base.appendingPathComponent(platform, isDirectory: true)
    }

    /// Writes a `JSONSerialization` value (dictionary, array, or scalar) and
    /// returns the file.
    @discardableResult
    static func emit(
        _ object: Any, schema: String, variant: String,
        directory: URL = outputDirectory(), schemas: URL = schemasDirectory
    ) throws -> URL {
        // JSONSerialization raises an Objective-C exception, not a Swift error,
        // on values it cannot write, so check first.
        guard JSONSerialization.isValidJSONObject(object) || isScalar(object) else {
            throw Failure.notJSON("\(type(of: object)) holds a value JSONSerialization cannot write")
        }
        try checkNames(schema: schema, variant: variant, schemas: schemas)
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed,
        ])
        return try write(bytes, schema: schema, variant: variant, directory: directory)
    }

    /// Writes an `Encodable` value and returns the file.
    @discardableResult
    static func emit<T: Encodable>(
        encodable value: T, schema: String, variant: String,
        directory: URL = outputDirectory(), schemas: URL = schemasDirectory
    ) throws -> URL {
        try checkNames(schema: schema, variant: variant, schemas: schemas)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try write(try encoder.encode(value), schema: schema, variant: variant, directory: directory)
    }

    /// Writes bytes that are already JSON, such as a request body captured by
    /// `StubURLProtocol`, after checking they parse. Keys come out sorted.
    @discardableResult
    static func emit(
        jsonData: Data, schema: String, variant: String,
        directory: URL = outputDirectory(), schemas: URL = schemasDirectory
    ) throws -> URL {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
        } catch {
            throw Failure.notJSON((error as NSError).localizedDescription)
        }
        return try emit(object, schema: schema, variant: variant, directory: directory, schemas: schemas)
    }

    // MARK: Private

    private static func isScalar(_ object: Any) -> Bool {
        object is String || object is NSNumber || object is NSNull
    }

    /// A dot in either name would break the `<schema>.<variant>.json` split,
    /// and a schema with no file would be skipped by the validator.
    private static func checkNames(schema: String, variant: String, schemas: URL) throws {
        guard isName(schema, allowUpper: false, allowUnderscore: false) else { throw Failure.badSchemaName(schema) }
        guard isName(variant, allowUpper: true, allowUnderscore: true) else { throw Failure.badVariantName(variant) }
        let schemaFile = schemas.appendingPathComponent("\(schema).schema.json")
        guard FileManager.default.fileExists(atPath: schemaFile.path) else {
            throw Failure.unknownSchema(schema, schemaFile)
        }
    }

    private static func isName(_ name: String, allowUpper: Bool, allowUnderscore: Bool) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.first else { return false }
        func word(_ c: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(c) || ("0"..."9").contains(c) || (allowUpper && ("A"..."Z").contains(c))
        }
        return word(first) && scalars.dropFirst().allSatisfy { c in
            word(c) || c == "-" || (allowUnderscore && c == "_")
        }
    }

    private static func write(_ bytes: Data, schema: String, variant: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(schema).\(variant).json")
        try (bytes + Data("\n".utf8)).write(to: file, options: .atomic)
        return file
    }
}
