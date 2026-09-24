import Foundation

/// Shared plumbing for the mock factories in this folder.
///
/// Every factory starts from a real captured payload (`contracts/samples`) or a
/// contract fixture (`contracts/fixtures/<schema>/valid`), read through
/// `Fixtures`, and applies overrides. Tests never inline external payloads.
/// `FactoryContractTests` emits every factory's default, every variant and
/// every sample to `contracts/out/ios`, and `scripts/coverage/ios.sh` checks
/// them against the schemas.
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

    private static func jsonFiles(in directory: String) throws -> [String] {
        let url = try Fixtures.url(directory)
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix("_") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }
}
