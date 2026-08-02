// SellwildHouseAd.swift — client-side house-ad backfill.
//
// When a paid creative is absent — a no-fill, or the transient blank while a
// `.prebidOnly` slot tears down one creative and renders the next on refresh —
// the ad slot would otherwise flash empty. House ads fill that gap with our own
// inventory, entirely client-side (no GAM house line items, which don't exist
// on the `.prebidOnly` path anyway).
//
// The mechanism is a BACKDROP: a house view sits *behind* the paid creative and
// shows through only when the slot is empty. When a real creative renders on
// top it covers the house ad, so the slot auto-reverts to the paid ad with no
// explicit "blank detected" event needed (there isn't one for the refresh gap).
//
// Content precedence, resolved per placement from remote config (no release):
//   1. CMS house image  — MOBILE_HOUSE_AD_IMAGE / MOBILE_HOUSE_AD_URL, with optional
//      per-size (MOBILE_HOUSE_AD_BY_SIZE) and per-zone (MOBILE_HOUSE_AD_BY_ZONE) overrides.
//   2. A Sellwild listing — supplied by the feed when no image is configured
//      (MREC only; a 320x50 banner is too small for a card).
//   3. Nothing — the slot stays empty, today's behavior.
//
// Master switch: MOBILE_HOUSE_AD_ENABLED (default true) kills all backfill, image and
// listing alike, so ops can revert to the plain-blank behavior remotely.
//
// Images are cached locally — in-memory plus an on-disk copy in the caches
// directory — so a house image is fetched from the network at most once per
// device, not once per empty slot. This is a deliberate request-saving measure.

import UIKit

/// A resolved house-ad creative: an image to render and an optional tap URL.
public struct SellwildHouseAdCreative: Equatable {
    public let imageURL: String
    public let clickURL: String?
}

public enum SellwildHouseAd {

    /// Whether house-ad backfill is enabled for this app. Defaults to `true`;
    /// set `MOBILE_HOUSE_AD_ENABLED: false` in the CDN config to disable all backfill
    /// (image and listing) and restore the plain-blank behavior.
    static func isEnabled(remoteValues: [String: Any]?) -> Bool {
        guard let raw = remoteValues?["MOBILE_HOUSE_AD_ENABLED"] else { return true }
        switch raw {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return !["0", "false", "no", "off"].contains(s.lowercased())
        default: return true
        }
    }

    /// Resolve the house image creative for a placement, most specific first:
    ///   1. MOBILE_HOUSE_AD_BY_ZONE[zoneId]      — { "image": ..., "url": ... }
    ///   2. MOBILE_HOUSE_AD_BY_SIZE["<w>x<h>"]   — { "image": ..., "url": ... }
    ///   3. MOBILE_HOUSE_AD_IMAGE + MOBILE_HOUSE_AD_URL — the app-wide default
    /// Returns `nil` when disabled or no image is configured (the caller then
    /// falls back to a listing, or leaves the slot empty).
    static func resolve(
        remoteValues: [String: Any]?,
        zoneId: String?,
        size: CGSize
    ) -> SellwildHouseAdCreative? {
        guard isEnabled(remoteValues: remoteValues), let raw = remoteValues else { return nil }

        if let zoneId,
           let byZone = raw["MOBILE_HOUSE_AD_BY_ZONE"] as? [String: Any],
           let creative = creative(from: byZone[zoneId]) {
            return creative
        }
        let sizeKey = "\(Int(size.width))x\(Int(size.height))"
        if let bySize = raw["MOBILE_HOUSE_AD_BY_SIZE"] as? [String: Any],
           let creative = creative(from: bySize[sizeKey]) {
            return creative
        }
        if let image = nonEmpty(raw["MOBILE_HOUSE_AD_IMAGE"]) {
            return SellwildHouseAdCreative(imageURL: image, clickURL: nonEmpty(raw["MOBILE_HOUSE_AD_URL"]))
        }
        return nil
    }

    /// Parse a `{ "image": ..., "url": ... }` override object into a creative.
    private static func creative(from value: Any?) -> SellwildHouseAdCreative? {
        guard let obj = value as? [String: Any], let image = nonEmpty(obj["image"]) else { return nil }
        return SellwildHouseAdCreative(imageURL: image, clickURL: nonEmpty(obj["url"]))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    // MARK: Local image cache (memory + disk)

    private static let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 16
        return c
    }()

    private static let diskDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("SellwildHouseAds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A stable (launch-independent) filename for a URL — djb2 hashed to hex, so
    /// the disk copy survives app restarts (unlike `URL.hashValue`).
    private static func diskURL(for urlString: String) -> URL? {
        guard let dir = diskDir else { return nil }
        var hash: UInt64 = 5381
        for byte in urlString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return dir.appendingPathComponent(String(format: "%016llx", hash))
    }

    /// Load a house image, memory cache → disk cache → network (populating both).
    /// The completion is always called on the main thread; `nil` on failure.
    static func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        let key = urlString as NSString
        if let cached = memoryCache.object(forKey: key) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let disk = diskURL(for: urlString),
               let data = try? Data(contentsOf: disk),
               let image = UIImage(data: data) {
                memoryCache.setObject(image, forKey: key)
                DispatchQueue.main.async { completion(image) }
                return
            }
            // http/https only (reject file:// etc. — the URL is remote config)
            // and cap the payload so a hostile oversized creative can't OOM.
            guard let url = SellwildSafeURL.imageURL(urlString),
                  let data = try? Data(contentsOf: url),
                  data.count <= SellwildSafeURL.maxImageBytes,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            memoryCache.setObject(image, forKey: key)
            if let disk = diskURL(for: urlString) { try? data.write(to: disk) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
