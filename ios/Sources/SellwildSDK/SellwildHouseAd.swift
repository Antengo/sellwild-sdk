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
    /// (image and listing) and restore the plain-blank behavior. Same coercion
    /// as every kill switch (FAILURES.md 5.3).
    static func isEnabled(remoteValues: [String: Any]?) -> Bool {
        SellwildFailuresCore.coerceFlag(remoteValues?["MOBILE_HOUSE_AD_ENABLED"])
    }

    /// Resolve the house image creative for a placement, most specific first:
    ///   1. MOBILE_HOUSE_AD_BY_ZONE[zoneId]      — { "image": ..., "url": ... }
    ///   2. MOBILE_HOUSE_AD_BY_SIZE["<w>x<h>"]   — { "image": ..., "url": ... }
    ///   3. MOBILE_HOUSE_AD_IMAGE + MOBILE_HOUSE_AD_URL — the app-wide default
    ///
    /// The image field (top-level `MOBILE_HOUSE_AD_IMAGE` or the `image` inside a
    /// by-zone / by-size object) accepts **either a single URL string or an array
    /// of URL strings**. For an array, one URL is chosen at random on each call —
    /// i.e. each no-fill — so backfill rotates. The chosen image is lazily
    /// fetched by `loadImage` and cached (memory + disk) per URL the first time
    /// it's selected. The click URL (`MOBILE_HOUSE_AD_URL` / `url`) is paired the
    /// same way: a single string is shared across all images, or an array pairs
    /// one click URL per image by index.
    ///
    /// Returns `nil` when disabled or no image is configured (the caller then
    /// falls back to a listing, or leaves the slot empty).
    static func resolve(
        remoteValues: [String: Any]?,
        zoneId: String?,
        size: CGSize
    ) -> SellwildHouseAdCreative? {
        var rng = SystemRandomNumberGenerator()
        return resolve(remoteValues: remoteValues, zoneId: zoneId, size: size, using: &rng)
    }

    /// `resolve` with the random source for the pick injected.
    static func resolve<R: RandomNumberGenerator>(
        remoteValues: [String: Any]?,
        zoneId: String?,
        size: CGSize,
        using rng: inout R
    ) -> SellwildHouseAdCreative? {
        candidates(remoteValues: remoteValues, zoneId: zoneId, size: size).randomElement(using: &rng)
    }

    /// Every creative the random pick in `resolve` chooses from, in order
    /// (pure): the first level with a usable image wins (by zone, then by
    /// size, then the app-wide default). Empty when disabled or when nothing
    /// is configured.
    static func candidates(
        remoteValues: [String: Any]?,
        zoneId: String?,
        size: CGSize
    ) -> [SellwildHouseAdCreative] {
        guard isEnabled(remoteValues: remoteValues), let raw = remoteValues else { return [] }

        if let zoneId, let byZone = raw["MOBILE_HOUSE_AD_BY_ZONE"] as? [String: Any] {
            let zone = candidates(from: byZone[zoneId])
            if !zone.isEmpty { return zone }
        }
        let sizeKey = "\(Int(size.width))x\(Int(size.height))"
        if let bySize = raw["MOBILE_HOUSE_AD_BY_SIZE"] as? [String: Any] {
            let sized = candidates(from: bySize[sizeKey])
            if !sized.isEmpty { return sized }
        }
        return candidates(image: raw["MOBILE_HOUSE_AD_IMAGE"], url: raw["MOBILE_HOUSE_AD_URL"])
    }

    /// The creatives of a `{ "image": ..., "url": ... }` override object.
    private static func candidates(from value: Any?) -> [SellwildHouseAdCreative] {
        guard let obj = value as? [String: Any] else { return [] }
        return candidates(image: obj["image"], url: obj["url"])
    }

    /// One creative per non-blank image. `image` and `url` are each a single
    /// URL string or an array of URL strings. The click URL pairs by the
    /// image's **original** index when `url` is an array (one per image); a
    /// single `url` string is shared across all images; a missing or blank
    /// paired entry yields no click.
    private static func candidates(image imageValue: Any?, url urlValue: Any?) -> [SellwildHouseAdCreative] {
        let images: [(index: Int, url: String)]
        if let arr = imageValue as? [Any] {
            images = arr.enumerated().compactMap { pair in
                nonEmpty(pair.element).map { (index: pair.offset, url: $0) }
            }
        } else if let single = nonEmpty(imageValue) {
            images = [(index: 0, url: single)]
        } else {
            images = []
        }
        return images.map { picked in
            // Click URL: array → paired by the image's original index; string → shared.
            let click: String?
            if let urls = urlValue as? [Any] {
                click = picked.index < urls.count ? nonEmpty(urls[picked.index]) : nil
            } else {
                click = nonEmpty(urlValue)
            }
            return SellwildHouseAdCreative(imageURL: picked.url, clickURL: click)
        }
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

    /// Empties the in-memory image cache (the disk copy stays).
    static func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// The on-disk cache directory, created once per launch. nil when there is
    /// none; the images are then cached in memory only.
    private static let diskDir: URL? = makeCacheDirectory(
        in: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    )

    /// Creates `SellwildHouseAds/` under `base` and returns it. When that
    /// fails it reports `storage.cache_dir.exception` and returns nil, so the
    /// disk cache is skipped instead of failing on every read and write.
    static func makeCacheDirectory(in base: URL?, fileManager: FileManager = .default) -> URL? {
        guard let base else { return nil }
        let dir = base.appendingPathComponent("SellwildHouseAds", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            SellwildFailures.log(code: .storageCacheDirException, component: .storage, severity: .warn, error: error,
                                 message: "house ad image cache directory could not be created")
            return nil
        }
    }

    /// A stable (launch-independent) filename for a URL — djb2 hashed to hex, so
    /// the disk copy survives app restarts (unlike `URL.hashValue`).
    static func diskURL(for urlString: String, in dir: URL) -> URL {
        var hash: UInt64 = 5381
        for byte in urlString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return dir.appendingPathComponent(String(format: "%016llx", hash))
    }

    /// Where house images come from. Partners always get `live`; tests swap
    /// `imageLoader` for a local download and a temporary directory.
    struct ImageLoader {
        /// Downloads an http(s) image. Completes on any queue.
        var download: (URL, @escaping (Result<Data, Error>) -> Void) -> Void
        /// The disk cache directory, or nil for memory only.
        var directory: () -> URL?

        static func live(session: URLSession = .shared) -> ImageLoader {
            ImageLoader(
                download: { url, completion in
                    session.dataTask(with: url) { data, response, error in
                        completion(SellwildHouseAd.downloadResult(data: data, response: response, error: error))
                    }.resume()
                },
                directory: { SellwildHouseAd.diskDir }
            )
        }
    }

    static var imageLoader = ImageLoader.live()

    /// A download that answered with an HTTP error status.
    struct HTTPStatusError: LocalizedError {
        let status: Int
        var errorDescription: String? { "HTTP \(status)" }
    }

    /// A completed image download as a result (pure): the transport error,
    /// an HTTP status outside 2xx, or the body (empty when there is none).
    static func downloadResult(data: Data?, response: URLResponse?, error: Error?) -> Result<Data, Error> {
        if let error { return .failure(error) }
        if let status = SellwildLoadFailure.httpFailureStatus(response) { return .failure(HTTPStatusError(status: status)) }
        return .success(data ?? Data())
    }

    /// Image bytes as an image, or why not (pure). Payloads over
    /// `SellwildSafeURL.maxImageBytes` are refused so a hostile creative
    /// cannot exhaust memory.
    static func decodeImage(_ data: Data?) -> Result<UIImage, ImageProblem> {
        guard let data else { return .failure(.undecodableDataURI) }
        guard data.count <= SellwildSafeURL.maxImageBytes else { return .failure(.tooLarge) }
        guard let image = UIImage(data: data) else { return .failure(.notAnImage) }
        return .success(image)
    }

    /// Why a house image was refused. Its raw value is the reported message.
    enum ImageProblem: String, Error {
        case undecodableDataURI = "data: URI could not be decoded"
        case tooLarge = "image is larger than the 8 MB cap"
        case notAnImage = "image data could not be decoded"
        case notHTTP = "image URL is not http(s)"
    }

    /// Load a house image, memory cache → disk cache → network (populating both).
    /// The completion is always called on the main thread; `nil` on failure.
    /// Each failure is reported once, here.
    static func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        let key = urlString as NSString
        if let cached = memoryCache.object(forKey: key) {
            completion(cached)
            return
        }
        let loader = imageLoader
        DispatchQueue.global(qos: .userInitiated).async {
            let deliver = { (image: UIImage?) in DispatchQueue.main.async { completion(image) } }
            // data: URI — listing photos from the static cache can be inline
            // base64 (the feed's own cell decodes these too). Decode inline,
            // size-capped; memory-cache only, no disk churn for a self-contained
            // value. Without this, a data: photo fails SellwildSafeURL.imageURL's
            // http/https check below and the slot shows a grey placeholder.
            if urlString.hasPrefix("data:") {
                switch decodeImage(decodeDataURI(urlString)) {
                case .success(let image):
                    memoryCache.setObject(image, forKey: key)
                    deliver(image)
                case .failure(let problem):
                    reportInvalid(problem, image: urlString, url: nil)
                    deliver(nil)
                }
                return
            }
            let disk = loader.directory().map { diskURL(for: urlString, in: $0) }
            // `try?`: no file yet is the normal cache miss, not a failure. An
            // unreadable copy falls through to the download, which rewrites it.
            if let disk, let data = try? Data(contentsOf: disk), let image = UIImage(data: data) {
                memoryCache.setObject(image, forKey: key)
                deliver(image)
                return
            }
            // http/https only (reject file:// etc. — the URL is remote config).
            guard let url = SellwildSafeURL.imageURL(urlString) else {
                reportInvalid(.notHTTP, image: urlString, url: urlString)
                deliver(nil)
                return
            }
            loader.download(url) { result in
                switch result.flatMap({ data in decodeImage(data).map { (data, $0) }.mapError { $0 as Error } }) {
                case .success(let (data, image)):
                    memoryCache.setObject(image, forKey: key)
                    if let disk { writeCache(data, to: disk) }
                    deliver(image)
                case .failure(let problem as ImageProblem):
                    reportInvalid(problem, image: urlString, url: urlString)
                    deliver(nil)
                case .failure(let error):
                    reportDownloadFailure(error, url: urlString)
                    deliver(nil)
                }
            }
        }
    }

    private static func writeCache(_ data: Data, to file: URL) {
        do {
            try data.write(to: file)
        } catch {
            SellwildFailures.log(code: .storageWriteException, component: .storage, severity: .warn, error: error,
                                 message: "house ad image could not be written to the disk cache")
        }
    }

    /// A refused image stays refused until the config (or the listing photo)
    /// changes, and every no-fill loads it again, so each problem is reported
    /// once per launch per image. A data: URI is keyed by its length and
    /// hash, not its text, which can be megabytes. A download that fails
    /// (`reportDownloadFailure`) can pass on the next try, so it is reported
    /// each time.
    private static func reportInvalid(_ problem: ImageProblem, image: String, url: String?) {
        let key = image.hasPrefix("data:") ? "data:\(image.utf8.count):\(image.hashValue)" : image
        guard SellwildReportOnce.first(.houseImageInvalid, "\(problem.rawValue)|\(key)") else { return }
        SellwildFailures.log(code: .houseImageInvalid, component: .house, severity: .warn,
                             message: problem.rawValue, url: url)
    }

    private static func reportDownloadFailure(_ error: Error, url: String) {
        if let http = error as? HTTPStatusError {
            SellwildFailures.log(code: .houseImageNetwork, component: .house, severity: .warn,
                                 message: "HTTP \(http.status)", httpStatus: http.status, url: url)
        } else if SellwildLoadFailure.transport(error) == .cancelled {
            SellwildLog.debug("[SellwildHouseAd] image download cancelled")
        } else {
            SellwildFailures.log(code: .houseImageNetwork, component: .house, severity: .warn, error: error, url: url)
        }
    }

    /// Decode a `data:[...];base64,<payload>` URI into raw bytes. Mirrors the
    /// feed cell's decoder so a listing served with an inline photo renders the
    /// same in the house backdrop as it does in the feed.
    static func decodeDataURI(_ s: String) -> Data? {
        guard let comma = s.firstIndex(of: ",") else { return nil }
        let payload = String(s[s.index(after: comma)...])
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    // MARK: Listing fallback selection

    /// Whether a listing carries a usable (non-empty) primary photo URL. A
    /// photoless listing renders as a grey placeholder, so the feed prefers to
    /// skip it when picking a house-backfill listing.
    static func hasUsablePhoto(_ listing: SellwildListing) -> Bool {
        guard let url = listing.photos?.first?.url else { return false }
        return !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Pick a listing to house-backfill an MREC slot, rotating by `row` so
    /// adjacent slots don't repeat. Prefers listings that actually have a photo
    /// (rotating within that subset); falls back to plain rotation over all
    /// listings only when none have a usable photo. `excludeIds` — the ids of
    /// listings already rendered as a normal row elsewhere in the same feed —
    /// are skipped so a house backfill never duplicates one, falling back to a
    /// duplicate only if every candidate in the pool is already shown. Returns
    /// nil when empty.
    static func pickListing(
        from listings: [SellwildListing],
        row: Int,
        excludeIds: Set<String> = []
    ) -> SellwildListing? {
        guard !listings.isEmpty else { return nil }
        let withPhoto = listings.filter(hasUsablePhoto)
        let pool = withPhoto.isEmpty ? listings : withPhoto
        let notShown = pool.filter { !excludeIds.contains($0.id) }
        let finalPool = notShown.isEmpty ? pool : notShown
        return finalPool[((row % finalPool.count) + finalPool.count) % finalPool.count]
    }
}
