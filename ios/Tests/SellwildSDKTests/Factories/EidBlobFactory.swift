import Foundation

/// An OpenRTB EID array (GrowthCode `eb`, partner `setEids`), schema `eid-blob`.
enum EidBlobFactory {

    static let schema = "eid-blob"
    static let defaultVariant = "full"

    /// Two sources (UID2 and ID5). `overrides` apply to the first entry.
    static func make(_ overrides: [String: Any] = [:]) throws -> [[String: Any]] {
        try variant(defaultVariant, overrides)
    }

    static func variant(_ name: String, _ overrides: [String: Any] = [:]) throws -> [[String: Any]] {
        var entries = try Factory.array("fixtures/\(schema)/valid/\(name).json")
        guard let first = entries.first else { throw Factory.Failure.emptyArray(name) }
        entries[0] = Factory.merge(first, overrides)
        return entries
    }

    /// One source with one uid.
    static func single(source: String, id: String, atype: Int? = nil) throws -> [[String: Any]] {
        var uid: [String: Any] = ["id": id]
        if let atype = atype { uid["atype"] = atype }
        return try variant("minimal", ["source": source, "uids": [uid]])
    }

    static func variantNames() throws -> [String] { try Factory.fixtureVariants(schema) }
}
