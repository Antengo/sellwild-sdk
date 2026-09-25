import Foundation

/// The pure half of `SellwildFeedView`: the COL1 schedule and the rows it
/// builds, the per-row GPIDs, the listings already on screen, what an ad row
/// shows on no-fill, and which URLs a tap may open. No I/O and no logging:
/// the feed reports what these return.
///
/// COL1 grammar, one token per row: `L` listing card, `G` GAM 300x250 ad
/// (zones from `mobileZids`, in order), `D` direct ad (the same as `G` for
/// now), `B` 320x50 banner (`mobileBannerZid`, else `bannerZid`, else
/// `bottomBannerZid`).
enum SellwildFeedLayout {

    enum Row {
        case header
        case listing(SellwildListing)
        case gamAd(zoneId: String)
        case directAd(zoneId: String)
        case banner(zoneId: String)

        /// The zone of an ad row; nil for the header and listings.
        var adZoneId: String? {
            switch self {
            case .gamAd(let zone), .directAd(let zone), .banner(let zone): return zone
            case .header, .listing: return nil
            }
        }
    }

    static let defaultSchedule = "LLGLLGLLG"

    /// COL1 trimmed and upper-cased, or the default when it is missing or
    /// blank.
    static func normalizeSchedule(_ raw: String?) -> String {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return s.isEmpty ? defaultSchedule : s
    }

    /// The zone for the `index`-th ad row, cycling through `zones`.
    static func pickZone(_ zones: [String], index: Int) -> String? {
        guard !zones.isEmpty else { return nil }
        return zones[index % zones.count]
    }

    /// The zones `G` and `D` rows draw from: `mobileZids` without empty ones.
    static func adZones(_ mobileZids: [String]) -> [String] {
        mobileZids.filter { !$0.isEmpty }
    }

    /// The zone of a `B` row: the first of the three that is set (an empty
    /// one counts as set, as it always has), else "".
    static func bannerZone(mobile: String?, banner: String?, bottom: String?) -> String {
        if let mobile { return mobile }
        if let banner { return banner }
        return bottom ?? ""
    }

    /// A schedule token that did not become a row. A missing listing is not
    /// here: a short feed simply has fewer listing rows.
    enum Skip: Equatable {
        /// `G` or `D` with no ad zone (`feed.ad_zone.missing`).
        case noAdZone
        /// `B` with no banner zone (`feed.ad_zone.missing`).
        case noBannerZone
        /// Not a COL1 token (`feed.layout.invalid`).
        case unknownToken(Character)
    }

    struct Layout {
        let rows: [Row]
        let skipped: [Skip]
    }

    /// The header, then one row per token while tokens last.
    static func build(schedule: String, listings: [SellwildListing], adZones: [String], bannerZone: String) -> Layout {
        var rows: [Row] = [.header]
        var skipped: [Skip] = []
        var remaining = listings.makeIterator()
        var adIndex = 0
        for token in schedule.uppercased() {
            switch token {
            case "L":
                if let listing = remaining.next() { rows.append(.listing(listing)) }
            case "G", "D":
                guard let zone = pickZone(adZones, index: adIndex) else {
                    skipped.append(.noAdZone)
                    continue
                }
                rows.append(token == "G" ? .gamAd(zoneId: zone) : .directAd(zoneId: zone))
                adIndex += 1
            case "B":
                guard !bannerZone.isEmpty else {
                    skipped.append(.noBannerZone)
                    continue
                }
                rows.append(.banner(zoneId: bannerZone))
            default:
                skipped.append(.unknownToken(token))
            }
        }
        return Layout(rows: rows, skipped: skipped)
    }

    /// The effective GPID per ad row, keyed by row index: each slot's base
    /// (from `base(zone)`) in row order, with bases shared by more than one
    /// slot made unique by `SellwildGpid.disambiguate` (`base#n`). A row whose
    /// base is nil gets no entry, so no gpid is sent for it.
    static func gpids(rows: [Row], base: (String) -> String?) -> [Int: String] {
        var adRowIndices: [Int] = []
        var bases: [String?] = []
        for (index, row) in rows.enumerated() {
            guard let zone = row.adZoneId else { continue }
            adRowIndices.append(index)
            bases.append(base(zone))
        }
        let values = SellwildGpid.disambiguate(bases)
        var out: [Int: String] = [:]
        for (slot, rowIndex) in adRowIndices.enumerated() {
            if let value = values[slot] { out[rowIndex] = value }
        }
        return out
    }

    /// Ids of the listings shown as listing rows, so an ad-slot backfill does
    /// not repeat one.
    static func shownListingIds(_ rows: [Row]) -> Set<String> {
        var ids = Set<String>()
        for row in rows {
            if case .listing(let listing) = row { ids.insert(listing.id) }
        }
        return ids
    }

    /// What an ad row shows on no-fill.
    enum NoFillView: Equatable {
        /// Keep the fixed slot: the ad view shows a CMS house image in it, or
        /// there is no listing to show instead.
        case adSlot
        /// Swap to the full-width listing card.
        case fallbackCard
    }

    static func noFillView(hasHouseImage: Bool, hasListing: Bool) -> NoFillView {
        hasHouseImage || !hasListing ? .adSlot : .fallbackCard
    }

    /// Why a tap URL was not opened (`feed.open_url.invalid`).
    enum OpenProblem: String, Error, Equatable {
        case missing = "there is no URL to open"
        case notHTTP = "the URL is not http(s)"
    }

    /// The URL a tap may open: http(s) only. SFSafariViewController traps on
    /// any other scheme, and these URLs come from remote listing and CMS data.
    static func openTarget(_ urlString: String?) -> Result<URL, OpenProblem> {
        guard let urlString, !urlString.isEmpty else { return .failure(.missing) }
        guard let url = SellwildSafeURL.external(urlString) else { return .failure(.notHTTP) }
        return .success(url)
    }
}
