import Foundation

/// The decisions the React Native bridge makes about what JS sent: which
/// props, config values, geo and eids it cannot use, and why. Foundation only,
/// with no React and no SDK types, so it can be checked without an RN host
/// app. The view managers and `SellwildRNModule` act on the answers and log
/// each problem with `SellwildFailures.log` (contracts/FAILURES.md).
enum SellwildRNBridgeRules {

    /// The size labels React Native JS accepts: the keys of AD_DIMENSIONS in
    /// react-native/src/bannerSizing.ts. JS reports any other label itself
    /// (`ad.size.invalid`), so the bridge reports only a label from this set
    /// that the native SDK has no size for. react-native/test/nativeGlue.test.ts
    /// keeps this list equal to the JS one.
    static let jsAdSizeLabels: Set<String> = ["300x250", "320x50", "728x90", "160x600", "300x600", "1x1"]

    /// Why the banner props cannot set up an ad (`bridge.props.invalid`), or
    /// nil when they can. Also nil for a missing size or a label JS does not
    /// accept: JS already reported that one as `ad.size.invalid`, and a
    /// failure is logged once.
    static func bannerPropsProblem(
        hasConfig: Bool,
        size: String?,
        zoneId: String?,
        nativeSupports: (String) -> Bool
    ) -> String? {
        if !hasConfig { return "the config prop is missing" }
        if zoneId == nil { return "the zoneId prop is missing" }
        guard let size = size, !nativeSupports(size) else { return nil }
        return jsAdSizeLabels.contains(size) ? "size \(size) has no native ad size" : nil
    }

    /// A config value the bridge reads as text: the text, or nil when it is
    /// absent or null. `problem` says why a value of another type was dropped
    /// (`bridge.config.invalid`).
    static func text(_ value: Any?, key: String) -> (value: String?, problem: String?) {
        switch value {
        case .none, is NSNull:
            return (nil, nil)
        case let text as String:
            return (text, nil)
        case let other?:
            return (nil, "\(key) is \(kind(of: other)), not text, so it was dropped")
        }
    }

    /// A config value the bridge reads as a list of text: the list, or nil
    /// when it is absent or null. `problem` says why it was dropped: it is not
    /// a list, or holds an entry that is not text.
    static func textList(_ value: Any?, key: String) -> (value: [String]?, problem: String?) {
        switch value {
        case .none, is NSNull:
            return (nil, nil)
        case let list as [String]:
            return (list, nil)
        case let list as [Any]:
            let bad = list.filter { !($0 is String) }.count
            return (nil, "\(key) has \(bad) of \(list.count) entries that are not text, so it was dropped")
        case let other?:
            return (nil, "\(key) is \(kind(of: other)), not a list, so it was dropped")
        }
    }

    /// Why a `prebidServer` config value cannot be used, so the default
    /// Prebid Server is used instead (`bridge.config.invalid`), or nil when it
    /// is absent, null or complete.
    static func prebidServerProblem(_ value: Any?) -> String? {
        switch value {
        case .none, is NSNull:
            return nil
        case let map as [String: Any]:
            let missing = ["accountId", "endpoint"].filter { !(map[$0] is String) }
            return missing.isEmpty ? nil : "prebidServer has no \(missing.joined(separator: " or ")) text, so the default Prebid Server is used"
        case let other?:
            return "prebidServer is \(kind(of: other)), not an object, so the default Prebid Server is used"
        }
    }

    /// The last problem reported for one view, so a re-render with the same
    /// bad props does not report it again (`bridge.props.invalid`, logged
    /// once).
    struct ReportOnce {
        private(set) var last: String?

        /// `problem` when it should be reported now, because it is not the
        /// last one reported; nil otherwise. A nil `problem` (the props are
        /// fine again) forgets the last one, so the same problem coming back
        /// is reported again.
        mutating func take(_ problem: String?) -> String? {
            if problem == last { return nil }
            last = problem
            return problem
        }
    }

    /// Why the remote config could not be serialized for the ad passthrough.
    struct RemoteNotJSON: Error, CustomStringConvertible {
        let description = "remote holds a value JSON cannot hold (NaN, infinity or a non-JSON type)"
    }

    /// `remote` as JSON data for the bidder passthrough. A value JSON cannot
    /// hold would make JSONSerialization raise an Objective-C exception,
    /// which Swift cannot catch, so it is checked first.
    static func remoteJSON(_ remote: Any) -> Result<Data, Error> {
        guard JSONSerialization.isValidJSONObject(remote) else { return .failure(RemoteNotJSON()) }
        do {
            return .success(try JSONSerialization.data(withJSONObject: remote, options: []))
        } catch {
            return .failure(error)
        }
    }

    /// The geo dictionary `setGeo` got, or `[:]` (clear) with a problem when it
    /// is not a dictionary keyed by text (`bridge.geo.invalid`). A dictionary
    /// is passed on as it is; `problem` then names the fields
    /// `SellwildGeo(bridged:)` drops for their type (geoFieldProblem).
    static func geoMap(_ value: Any?) -> (map: [String: Any], problem: String?) {
        switch value {
        case let map as [String: Any]:
            return (map, geoFieldProblem(map))
        case .none, is NSNull:
            return ([:], "geo is null, not an object, so geo was cleared")
        case let other?:
            return ([:], "geo is \(kind(of: other)), not an object, so geo was cleared")
        }
    }

    /// Why the geo inside a config prop, or some of its fields, was dropped
    /// (`bridge.config.invalid`), or nil. The config keeps the rest, as
    /// before: a geo that is not an object is dropped whole, and a field of
    /// the wrong type is dropped by `SellwildGeo(bridged:)` (geoFieldProblem).
    /// Absent or null: no geo, and no problem.
    static func configGeoProblem(_ value: Any?) -> String? {
        switch value {
        case .none, is NSNull:
            return nil
        case let map as [String: Any]:
            return geoFieldProblem(map)
        case let other?:
            return "geo is \(kind(of: other)), not an object, so it was dropped"
        }
    }

    /// The geo fields `SellwildGeo(bridged:)` reads as text (`as? String`).
    static let geoTextFields = ["country", "state", "city", "zip", "metro"]

    /// The geo fields `SellwildGeo(bridged:)` reads as numbers (`as? NSNumber`).
    static let geoNumberFields = ["lat", "lon", "type"]

    /// The geo fields of a type `SellwildGeo(bridged:)` does not read, which
    /// it drops while it keeps the others: a text field that is not text, a
    /// number field that is not an NSNumber. Absent and null fields are
    /// unset, not problems. nil when there is none. The text matches the
    /// Android bridge (RnBridgeRules.geoWrongTyped).
    static func geoFieldProblem(_ map: [String: Any]) -> String? {
        var problems: [String] = []
        for key in geoTextFields {
            guard let value = map[key], !(value is NSNull), !(value is String) else { continue }
            problems.append("geo.\(key) is \(kind(of: value)), not text, so it was dropped")
        }
        for key in geoNumberFields {
            guard let value = map[key], !(value is NSNull), !(value is NSNumber) else { continue }
            problems.append("geo.\(key) is \(kind(of: value)), not a number, so it was dropped")
        }
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    /// One eid as the bridge passes it on: the source and its uids.
    struct Eid {
        let source: String
        let uids: [Uid]
    }

    /// One uid of an eid.
    struct Uid {
        let id: String
        let atype: Int
        let ext: [String: Any]?
    }

    /// The eids `setExternalUserIds` got, as it has always read them: a list
    /// with an entry that is not an object sets none; an entry without source
    /// or a uids list of objects is skipped, and so is a uid without id.
    /// `problem` says what was dropped (`bridge.eids.invalid`), or is nil when
    /// nothing was.
    static func eids(_ value: Any?) -> (eids: [Eid], problem: String?) {
        switch value {
        case .none, is NSNull:
            return ([], nil)
        case let list as [[String: Any]]:
            return eids(in: list)
        case let list as [Any]:
            let bad = list.filter { !($0 is [String: Any]) }.count
            return ([], "eids has \(bad) of \(list.count) entries that are not objects, so no eids were set")
        case let other?:
            return ([], "eids is \(kind(of: other)), not a list, so no eids were set")
        }
    }

    private static func eids(in list: [[String: Any]]) -> (eids: [Eid], problem: String?) {
        var skippedEntries = 0
        var skippedUids = 0
        var out: [Eid] = []
        for entry in list {
            guard let source = entry["source"] as? String,
                  let rawUids = entry["uids"] as? [[String: Any]] else {
                skippedEntries += 1
                continue
            }
            var uids: [Uid] = []
            for uid in rawUids {
                guard let id = uid["id"] as? String else {
                    skippedUids += 1
                    continue
                }
                let atype = (uid["atype"] as? NSNumber)?.intValue ?? 0
                uids.append(Uid(id: id, atype: atype, ext: uid["ext"] as? [String: Any]))
            }
            out.append(Eid(source: source, uids: uids))
        }
        if skippedEntries == 0 && skippedUids == 0 { return (out, nil) }
        return (out, "skipped \(skippedEntries) of \(list.count) eids without source or a uids list, and \(skippedUids) uids without id")
    }

    /// A short name for the type of a bridged value, for problem text. Never
    /// the value itself.
    static func kind(of value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "a boolean" : "a number"
        case is String: return "text"
        case is [Any]: return "a list"
        case is [AnyHashable: Any]: return "an object"
        default: return "\(type(of: value))"
        }
    }
}
