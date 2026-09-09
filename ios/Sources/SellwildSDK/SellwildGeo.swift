// SellwildGeo.swift — partner-supplied geo, emitted as OpenRTB `device.geo` on
// every native Prebid auction, and used to key per-state listing caches.
//
// Host apps (e.g. a weather app) usually know the user's location — state, zip,
// city, lat/lon — well before the ad SDK would. Passing it in lets DSPs value
// the impression on real geo instead of coarse IP, and lets the listings feed
// load a state-specific cache. The SDK never geocodes; the partner supplies
// resolved values via `SellwildConfig.geo` or `SellwildPrebidMobile.setGeo(_:)`.

import Foundation

/// Partner-supplied geo. All fields optional — only the ones you set are sent.
public struct SellwildGeo: Codable, Equatable {
    /// ISO-3166-1 alpha-3 country code (OpenRTB `device.geo.country`), e.g. "USA".
    public var country: String?
    /// State / region (OpenRTB `device.geo.region`). Also used to key per-state
    /// listing caches. Pass whatever your backend keys on (e.g. "NY").
    public var state: String?
    /// City name (OpenRTB `device.geo.city`).
    public var city: String?
    /// Postal / ZIP code (OpenRTB `device.geo.zip`).
    public var zip: String?
    /// Google metro / DMA code (OpenRTB `device.geo.metro`).
    public var metro: String?
    /// Latitude (OpenRTB `device.geo.lat`).
    public var lat: Double?
    /// Longitude (OpenRTB `device.geo.lon`).
    public var lon: Double?
    /// Geo source (OpenRTB `device.geo.type`): 1 = GPS/Location Services,
    /// 2 = IP, 3 = user-provided. Leave nil to omit.
    public var type: Int?

    public init(country: String? = nil, state: String? = nil, city: String? = nil,
                zip: String? = nil, metro: String? = nil, lat: Double? = nil,
                lon: Double? = nil, type: Int? = nil) {
        self.country = country
        self.state = state
        self.city = city
        self.zip = zip
        self.metro = metro
        self.lat = lat
        self.lon = lon
        self.type = type
    }

    /// OpenRTB `device.geo` object — only the non-empty fields. Maps `state`
    /// onto the ORTB `region` key.
    var ortbGeoDict: [String: Any] {
        var g: [String: Any] = [:]
        if let v = country, !v.isEmpty { g["country"] = v }
        if let v = state, !v.isEmpty { g["region"] = v }
        if let v = city, !v.isEmpty { g["city"] = v }
        if let v = zip, !v.isEmpty { g["zip"] = v }
        if let v = metro, !v.isEmpty { g["metro"] = v }
        if let v = lat { g["lat"] = v }
        if let v = lon { g["lon"] = v }
        if let v = type { g["type"] = v }
        return g
    }

    /// Map an ISO-3166-1 alpha-2 country code to alpha-3 for North America only
    /// (oRTB `device.geo.country` wants alpha-3). Returns nil for anything
    /// outside this set, so callers skip sending an unmapped country.
    static func northAmericaAlpha3(alpha2: String) -> String? {
        switch alpha2.uppercased() {
        case "US": return "USA"   // United States
        case "CA": return "CAN"   // Canada
        case "MX": return "MEX"   // Mexico
        case "GT": return "GTM"   // Guatemala
        case "BZ": return "BLZ"   // Belize
        case "SV": return "SLV"   // El Salvador
        case "HN": return "HND"   // Honduras
        case "NI": return "NIC"   // Nicaragua
        case "CR": return "CRI"   // Costa Rica
        case "PA": return "PAN"   // Panama
        case "GL": return "GRL"   // Greenland
        case "BM": return "BMU"   // Bermuda
        case "PM": return "SPM"   // Saint-Pierre & Miquelon
        default: return nil
        }
    }
}

/// Process-wide current geo, readable by ANY SDK surface — the native ads path,
/// the listings feed, or host-app code — not just the Prebid auction. Seeded
/// from `SellwildConfig.geo` at bootstrap and updated by
/// `SellwildPrebidMobile.setGeo(_:)`. Thread-safe.
///
/// This is the single source of truth for "where is the user"; the Prebid
/// bridge reads from it rather than owning geo privately, so future consumers
/// (e.g. per-state listing caches) can read the same value without going
/// through the ad path.
public enum SellwildGeoStore {
    private static let lock = NSLock()
    private static var _current: SellwildGeo?

    /// The current geo, or nil if none has been set. Reads/writes are locked.
    public static var current: SellwildGeo? {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); defer { lock.unlock() }; _current = newValue }
    }
}

public extension SellwildGeo {
    /// Build from a bridged JS payload (React Native `NSDictionary`). Returns nil
    /// when no usable field is present, so a caller can clear geo by sending `{}`.
    init?(bridged map: [String: Any]) {
        self.init(
            country: map["country"] as? String,
            state: map["state"] as? String,
            city: map["city"] as? String,
            zip: map["zip"] as? String,
            metro: map["metro"] as? String,
            lat: (map["lat"] as? NSNumber)?.doubleValue,
            lon: (map["lon"] as? NSNumber)?.doubleValue,
            type: (map["type"] as? NSNumber)?.intValue
        )
        if ortbGeoDict.isEmpty { return nil }
    }
}
