import CoreGraphics
import Foundation

/// The pure decisions behind `SellwildAdView`: refresh caps and floors, the
/// Prebid cold-start wait, remote flags, resume and detach, the GAM ad unit,
/// the house backdrop, placement validation, which ad errors are no-fill and
/// the native labels. No I/O and no logging: the view acts on what these
/// return and reports the failures.
enum SellwildAdPolicy {

    // MARK: Refresh

    /// Floor for both refresh timers, so a mis-scaled `AD_REFRESH_INTERVAL`
    /// (a seconds value read as milliseconds) cannot drive a refresh storm.
    static let minRefreshInterval: TimeInterval = 10

    /// The mobile refresh cap: `AD_REFRESH_MAX_MOBILE` when set, else the
    /// shared `AD_REFRESH_MAX` (as on Android and the web).
    static func refreshMax(mobile: Int, shared: Int) -> Int {
        mobile > 0 ? mobile : shared
    }

    /// The refresh interval, floored at `minRefreshInterval`.
    static func refreshInterval(_ configured: TimeInterval) -> TimeInterval {
        max(configured, minRefreshInterval)
    }

    /// Whether one more refresh may be scheduled: refresh is on and `count`
    /// is under `max`.
    static func mayRefresh(count: Int, max: Int) -> Bool {
        max > 0 && count < max
    }

    /// Whether the Prebid rendering banner must stop its own auto-refresh
    /// after the render that brought its render count to `count` (the first
    /// render plus each refresh). The fork's refresh is otherwise unbounded.
    static func prebidRefreshSpent(count: Int, max: Int) -> Bool {
        max > 0 && count > max
    }

    // MARK: Prebid cold start

    /// Prebid init is async and can race the first load: wait up to about
    /// 1.2 s (8 tries, 0.15 s apart), then load anyway.
    static let maxPrebidWaitAttempts = 8
    static let prebidWaitInterval: TimeInterval = 0.15

    /// What a load does while Prebid init may still be running.
    enum ColdStart: Equatable {
        /// Prebid is ready: run the auction.
        case ready
        /// Not ready yet: try again after `prebidWaitInterval`.
        case wait
        /// Still not ready after the whole wait: load anyway
        /// (`ad.prebid_init.timeout`).
        case timedOut
    }

    static func coldStart(ready: Bool, attempts: Int, maxAttempts: Int = maxPrebidWaitAttempts) -> ColdStart {
        if ready { return .ready }
        return attempts < maxAttempts ? .wait : .timedOut
    }

    // MARK: Remote flags

    /// `MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH`: keep a rendered `.prebidOnly`
    /// creative on reattach so its viewability tracker can fire (default off).
    static let keepCreativeOnReattachKey = "MOBILE_PREBID_KEEP_CREATIVE_ON_REATTACH"
    /// `MOBILE_PAUSE_REFRESH_DETACHED`: pause refresh while the view is off the
    /// window (default on).
    static let pauseRefreshWhenDetachedKey = "MOBILE_PAUSE_REFRESH_DETACHED"

    /// A remote on/off flag: a Bool, a number (non-zero is on), or text that
    /// is "1", "true", "yes" or "on" in any case (other text is off). Anything
    /// else, a missing key included, is `defaultValue`.
    static func flag(_ value: Any?, default defaultValue: Bool) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return defaultValue
        }
    }

    // MARK: Resume and detach

    /// What `resume()` does.
    enum ResumeAction: Equatable {
        /// The first auction never finished (paused in the cold-start wait):
        /// load again.
        case reload
        /// GAM: restart the refresh timer; the creative stays.
        case scheduleRefresh
        /// Prebid: keep the rendered creative so its tracker can fire, and
        /// re-auction after one refresh interval.
        case keepPrebidCreative
        /// Prebid: re-auction now, which un-latches pause()'s stopRefresh.
        case reloadPrebid
        /// Prebid with refresh off: nothing.
        case none
    }

    /// `keepCreative` is read only when there is a rendered creative to keep.
    static func resumeAction(needsReload: Bool, stack: SellwildAdStack, refreshMax: Int,
                             hasRenderedCreative: Bool, keepCreative: @autoclosure () -> Bool) -> ResumeAction {
        if needsReload { return .reload }
        switch stack {
        case .both, .gamOnly:
            return .scheduleRefresh
        case .prebidOnly:
            guard refreshMax > 0 else { return .none }
            return hasRenderedCreative && keepCreative() ? .keepPrebidCreative : .reloadPrebid
        }
    }

    /// What moving to or off a window does.
    enum DetachAction: Equatable {
        case pause, resume, none
    }

    static func detachAction(enabled: Bool, attached: Bool, pausedForDetach: Bool) -> DetachAction {
        guard enabled else { return .none }
        if !attached { return pausedForDetach ? .none : .pause }
        return pausedForDetach ? .resume : .none
    }

    // MARK: GAM ad unit

    /// Google's test ad units. /6499/example/banner fills only 320x50; the
    /// adaptive unit fills 300x250, 728x90, 300x600 and 160x600.
    static let gamTestAdUnitBanner = "/6499/example/banner"
    static let gamTestAdUnitAdaptive = "/21775744923/example/adaptive-banner"

    struct GAMAdUnit: Equatable {
        let id: String
        /// Neither `gamTag` nor `GAM` is set, so Google's test unit is used
        /// (`ad.gam_unit.missing`).
        let isTestFallback: Bool
    }

    /// The GAM ad unit: `gamTag`, else the raw `GAM` value, else a
    /// size-appropriate Google test unit (as on Android).
    static func gamAdUnit(gamTag: String?, remoteGAM: Any?, size: CGSize) -> GAMAdUnit {
        if let gamTag, !gamTag.isEmpty { return GAMAdUnit(id: gamTag, isTestFallback: false) }
        if let remote = remoteGAM as? String, !remote.isEmpty { return GAMAdUnit(id: remote, isTestFallback: false) }
        let banner = size.width == 320 && size.height == 50
        return GAMAdUnit(id: banner ? gamTestAdUnitBanner : gamTestAdUnitAdaptive, isTestFallback: true)
    }

    // MARK: House backdrop

    /// What the house backdrop shows.
    enum HouseContent<Image, Listing> {
        case image(Image)
        case listing(Listing)
        case none
    }

    /// Precedence: the CMS house image, then a feed-supplied listing (MREC
    /// and larger only; a 320x50 banner is too small for a card), else
    /// nothing. Nothing is by design, not a failure.
    static func houseContent<Image, Listing>(enabled: Bool, image: Image?, listing: Listing?,
                                             size: CGSize) -> HouseContent<Image, Listing> {
        guard enabled else { return .none }
        if let image { return .image(image) }
        if let listing, isMREC(size) { return .listing(listing) }
        return .none
    }

    static func isMREC(_ size: CGSize) -> Bool {
        size.width >= 300 && size.height >= 250
    }

    // MARK: Placement

    /// The winning Prebid bid, as far as placement validation needs it.
    struct BidSummary: Equatable {
        var isVideoFormat = false
        var hasVideoConfig = false
        var adm: String?
    }

    struct Placement: Equatable {
        /// A video creative won a zone that did not ask for video
        /// (`placementMismatch`, `ad.placement.invalid`).
        let mismatch: Bool
        /// Mute every player in the creative.
        let muted: Bool
    }

    /// nil when the winning bid is not video, so there is nothing to enforce.
    /// `soundEnabled` is read only for a zone that asked for video.
    static func placement(bid: BidSummary?, expectedVideo: Bool, soundEnabled: @autoclosure () -> Bool) -> Placement? {
        guard let bid, bid.isVideoFormat || bid.hasVideoConfig || bid.adm?.contains("<VAST") == true else { return nil }
        return Placement(mismatch: !expectedVideo, muted: !(expectedVideo && soundEnabled()))
    }

    // MARK: No-fill (FAILURES.md 4.3: not a failure)

    /// GMA's error domain (`GADErrorDomain`).
    static let gamErrorDomain = "com.google.admob"
    /// `GADErrorNoFill` (1), and the mediation no-fill (9) older SDKs send.
    static let gamNoFillCodes: Set<Int> = [1, 9]

    /// Whether a GAM load error is a no-fill, which the `adError` event
    /// covers.
    static func isGAMNoFill(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == gamErrorDomain && gamNoFillCodes.contains(ns.code)
    }

    /// The Prebid fork's error domain, and the userInfo key that carries the
    /// `ResultCode` (`PrebidConstants.FETCH_DEMAND_RESULT_KEY`).
    static let prebidErrorDomain = "org.prebid.mobile"
    static let prebidResultCodeKey = "PrebidResultCodeKey"
    /// `ResultCode.prebidDemandFetchSuccess`.
    static let prebidSuccessCode = 0
    /// `ResultCode.prebidDemandNoBids` (7) and `.prebidDemandNoCachedBids` (11).
    static let prebidNoBidCodes: Set<Int> = [7, 11]

    /// Whether a Prebid rendering error is a no-bid, which the `adError`
    /// event covers.
    static func isPrebidNoFill(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == prebidErrorDomain, let code = ns.userInfo[prebidResultCodeKey] as? NSNumber else { return false }
        return prebidNoBidCodes.contains(code.intValue)
    }

    /// Whether an auction `ResultCode` (its raw value) is a failure: neither
    /// success nor no-bids.
    static func isAuctionFailure(_ resultCode: Int) -> Bool {
        resultCode != prebidSuccessCode && !prebidNoBidCodes.contains(resultCode)
    }

    // MARK: Native labels

    /// "Sponsored · <advertiser>", or "Sponsored" with no advertiser.
    static func sponsoredText(_ sponsoredBy: String?) -> String {
        if let sponsoredBy { return "Sponsored · \(sponsoredBy)" }
        return "Sponsored"
    }

    /// The call to action, or "Learn more" when it is missing or empty.
    static func callToActionText(_ callToAction: String?) -> String {
        if let callToAction, !callToAction.isEmpty { return callToAction }
        return "Learn more"
    }
}
