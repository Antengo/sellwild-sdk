import Foundation

/// Shared plumbing for the mock factories in this folder.
///
/// Every factory starts from a real captured payload (`contracts/samples`) or a
/// contract fixture (`contracts/fixtures/<schema>/valid`), read through
/// `Fixtures`, and applies overrides. Tests never inline external payloads.
/// `FactoryContractTests` emits every factory's default, every variant and
/// every sample to `contracts/out/ios`, and `scripts/coverage/ios.sh` checks
/// them against the schemas.
///
/// Every payload a factory builds with overrides is also emitted, as
/// `<schema>.used-<hash>.json`, so the validator checks exactly what the
/// tests feed the SDK, not a copied list. A test that breaks a payload on
/// purpose (a robustness or failure-path input) builds it inside
/// `Factory.offSchema(because:)`, which says why and keeps it out of that
/// check.
enum Factory {

    enum Failure: Error, CustomStringConvertible, Equatable {
        case notAnObject(String)
        case notAnArray(String)
        case emptyArray(String)
        case dropped(String)

        var description: String {
            switch self {
            case .notAnObject(let path): return "\(path) is not a JSON object"
            case .notAnArray(let path): return "\(path) is not a JSON array"
            case .emptyArray(let path): return "\(path) is an empty array"
            case .dropped(let reason): return "the pure core dropped the failure: \(reason)"
            }
        }
    }

    /// A contract file as a JSON object, without the fixture markers.
    static func object(_ path: String) throws -> [String: Any] {
        guard let object = try Fixtures.json(path) as? [String: Any] else { throw Failure.notAnObject(path) }
        return stripMarkers(object)
    }

    /// A contract file as a JSON array of objects, without the fixture markers.
    static func array(_ path: String) throws -> [[String: Any]] {
        guard let array = try Fixtures.json(path) as? [[String: Any]] else { throw Failure.notAnArray(path) }
        return array.map(stripMarkers)
    }

    /// Removes the `_synthetic` / `_note` markers hand-made fixtures carry.
    /// They are never part of a real payload.
    static func stripMarkers(_ object: [String: Any]) -> [String: Any] {
        object.filter { !$0.key.hasPrefix("_") }
    }

    /// An override value that removes the key: `["remote_url": Factory.remove]`.
    /// `NSNull()` sets a JSON null instead.
    static let remove = Remove()
    struct Remove {}

    /// `base` with `overrides` applied, key by key.
    static func merge(_ base: [String: Any], _ overrides: [String: Any]) -> [String: Any] {
        var out = base
        for (key, value) in overrides {
            out[key] = value is Remove ? nil : value
        }
        return out
    }

    /// Names (file names without `.json`) of `fixtures/<schema>/valid/*`.
    static func fixtureVariants(_ schema: String) throws -> [String] {
        try jsonFiles(in: "fixtures/\(schema)/valid")
    }

    /// Names of the real JSON samples in `samples/<directory>` (not the
    /// captured 403 XML bodies).
    static func sampleNames(_ directory: String) throws -> [String] {
        try jsonFiles(in: "samples/\(directory)")
    }

    /// A variant name `ContractEmitter` accepts: dots become dashes.
    static func variantName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "-")
    }

    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: Payloads the tests use

    private static let lock = NSLock()
    private static var offSchemaReasons: [String] = []

    /// Runs `body`, whose factory payloads break their schema on purpose:
    /// `reason` says how. They are written to `<out>/.ios-off-schema/`
    /// (the validator skips dot folders), not to `<out>/ios`.
    ///
    ///     let raw = try Factory.offSchema(because: "GPID_BASE must be text") {
    ///         try AppConfigFactory.remote(["GPID_BASE": 12345])
    ///     }
    static func offSchema<T>(because reason: String, _ body: () throws -> T) rethrows -> T {
        precondition(!reason.trimmingCharacters(in: .whitespaces).isEmpty, "say why the payload is off-schema")
        lock.lock()
        offSchemaReasons.append(reason)
        lock.unlock()
        defer {
            lock.lock()
            offSchemaReasons.removeLast()
            lock.unlock()
        }
        return try body()
    }

    /// Emits `payload`, which a factory built with overrides, and returns it.
    /// Inside `offSchema(because:)` it goes to the off-schema folder instead.
    @discardableResult
    static func used<T>(_ payload: T, schema: String) throws -> T {
        let bytes = try data(payload)
        let variant = "used-\(fnv1a(bytes))"
        lock.lock()
        let offSchema = !offSchemaReasons.isEmpty
        lock.unlock()
        if offSchema {
            let directory = ContractEmitter.outputDirectory().deletingLastPathComponent()
                .appendingPathComponent(".ios-off-schema", isDirectory: true)
            try ContractEmitter.emit(payload, schema: schema, variant: variant, directory: directory)
        } else {
            try ContractEmitter.emit(payload, schema: schema, variant: variant)
        }
        return payload
    }

    /// FNV-1a 64 of `bytes`, as 16 hex digits: a stable name per payload.
    private static func fnv1a(_ bytes: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    private static func jsonFiles(in directory: String) throws -> [String] {
        let url = try Fixtures.url(directory)
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix("_") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }
}
