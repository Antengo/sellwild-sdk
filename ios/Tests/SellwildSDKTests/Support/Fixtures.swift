import Foundation

/// Reads shared contract files (schemas, fixtures, golden vectors, the failure
/// code registry) from the repo's `contracts/` directory.
///
/// SwiftPM resources cannot live outside the target directory, so the path is
/// found from this file's `#filePath` at compile time. Tests run in the
/// simulator, which reads the host file system, so the path works there too.
///
///     let vectors = try Fixtures.dict("golden/log-failure.vectors.json")
///
/// Paths are relative to `contracts/` and may not climb out of it.
enum Fixtures {

    enum Failure: Error, CustomStringConvertible, Equatable {
        case outsideContracts(String)
        case missing(URL)
        case notJSON(URL, String)
        case notObject(URL)

        var description: String {
            switch self {
            case .outsideContracts(let path):
                return "Fixture path \"\(path)\" must stay inside contracts/"
            case .missing(let url):
                return "Fixture not found: \(url.path)"
            case .notJSON(let url, let reason):
                return "Fixture is not valid JSON: \(url.path): \(reason)"
            case .notObject(let url):
                return "Fixture is not a JSON object: \(url.path)"
            }
        }
    }

    /// The repo root: this file sits in `ios/Tests/SellwildSDKTests/Support/`.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support
        .deletingLastPathComponent()  // SellwildSDKTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()

    static let contractsDirectory: URL = repoRoot.appendingPathComponent("contracts", isDirectory: true)

    /// The absolute URL of `path` under `root` (default `contracts/`).
    static func url(_ path: String, root: URL = contractsDirectory) throws -> URL {
        let base = root.standardizedFileURL
        let resolved = base.appendingPathComponent(path).standardizedFileURL
        guard !path.hasPrefix("/"), resolved.path.hasPrefix(base.path + "/") else {
            throw Failure.outsideContracts(path)
        }
        return resolved
    }

    /// The raw bytes of a contract file.
    static func data(_ path: String, root: URL = contractsDirectory) throws -> Data {
        let file = try url(path, root: root)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw Failure.missing(file)
        }
        return try Data(contentsOf: file)
    }

    /// A contract file parsed as JSON (object, array, or scalar).
    static func json(_ path: String, root: URL = contractsDirectory) throws -> Any {
        let bytes = try data(path, root: root)
        do {
            return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        } catch {
            throw Failure.notJSON(try url(path, root: root), (error as NSError).localizedDescription)
        }
    }

    /// A contract file whose top level must be a JSON object.
    static func dict(_ path: String, root: URL = contractsDirectory) throws -> [String: Any] {
        guard let object = try json(path, root: root) as? [String: Any] else {
            throw Failure.notObject(try url(path, root: root))
        }
        return object
    }
}
