import XCTest
import UIKit
import AVFoundation
import GoogleMobileAds
import SellwildPrebidSDK
@testable import SellwildSDK

/// Timers the tests fire by hand instead of waiting.
final class ManualScheduler: SellwildScheduler {

    final class Item: SellwildScheduled {
        let interval: TimeInterval
        let work: () -> Void
        private(set) var cancelled = false

        init(interval: TimeInterval, work: @escaping () -> Void) {
            self.interval = interval
            self.work = work
        }

        func cancel() {
            cancelled = true
        }
    }

    private(set) var items: [Item] = []

    /// Intervals of the timers still pending, oldest first.
    var pending: [TimeInterval] { items.filter { !$0.cancelled }.map(\.interval) }

    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> SellwildScheduled {
        let item = Item(interval: interval, work: work)
        items.append(item)
        return item
    }

    /// Runs the timers pending now, once each. Timers they schedule wait for
    /// the next call.
    func fire() {
        let due = items.filter { !$0.cancelled }
        for item in due { item.cancel() }
        for item in due { item.work() }
    }
}

/// GMA and Prebid for `SellwildAdView`, recorded instead of called.
final class FakeAdNetwork: SellwildAdNetwork {

    struct Auction {
        let banner: AdManagerBannerView
        let configId: String
        let adSizes: [CGSize]
        let gpid: String?
        let video: Bool
        let completion: (ResultCode) -> Void
    }

    var ready = false
    var bid: SellwildAdPolicy.BidSummary?
    private(set) var bootstraps: [String] = []
    private(set) var gamLoads: [AdManagerBannerView] = []
    private(set) var auctions: [Auction] = []
    private(set) var prebidLoads: [PrebidBannerView] = []

    func bootstrap(_ config: SellwildConfig) {
        bootstraps.append(config.partnerCode)
    }

    func isPrebidReady() -> Bool {
        ready
    }

    func loadGAM(_ banner: AdManagerBannerView) {
        gamLoads.append(banner)
    }

    func runBannerAuction(on banner: AdManagerBannerView, configId: String, adSizes: [CGSize], gpid: String?,
                          video: Bool, completion: @escaping (ResultCode) -> Void) {
        auctions.append(Auction(banner: banner, configId: configId, adSizes: adSizes, gpid: gpid, video: video,
                                completion: completion))
    }

    func loadPrebid(_ banner: PrebidBannerView) {
        prebidLoads.append(banner)
    }

    func winningBid(of banner: PrebidBannerView) -> SellwildAdPolicy.BidSummary? {
        bid
    }
}

/// An events queue whose batches are captured, with a clock that never
/// fires on its own.
final class EventRecorder {
    let transport = CapturingEventTransport()
    let clock = ManualEventClock()
    private(set) lazy var client = SellwildAPIClient(session: StubURLProtocol.makeSession(),
                                                     eventTransport: transport.transport, eventClock: clock.clock)

    /// Every event sent so far, flushed first.
    func events() -> [[String: Any]] {
        client.flushEvents()
        client.waitForEventQueue()
        return transport.batches.flatMap { $0 }
    }

    /// `event` of every event sent so far.
    func names() -> [String] {
        events().compactMap { $0["event"] as? String }
    }
}

/// Records every `SellwildAdViewDelegate` call.
final class AdViewDelegateRecorder: NSObject, SellwildAdViewDelegate {
    var calls: [String] = []
    var errors: [Error] = []
    var sizes: [CGSize] = []

    func sellwildAdViewDidLoad(_ adView: SellwildAdView) { calls.append("load") }
    func sellwildAdView(_ adView: SellwildAdView, didReceiveImpressionForZoneId zoneId: String) { calls.append("impression \(zoneId)") }
    func sellwildAdViewDidRecordClick(_ adView: SellwildAdView) { calls.append("click") }
    func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) {
        calls.append("fail")
        errors.append(error)
    }
    func sellwildAdView(_ adView: SellwildAdView, didRenderWithSize size: CGSize) {
        calls.append("size")
        sizes.append(size)
    }
    func sellwildAdView(_ adView: SellwildAdView, didRecordHouseImpressionForZoneId zoneId: String) {
        calls.append("house \(zoneId)")
    }
}

/// A view controller in a window, so views added to it find a presenter and
/// a window.
final class Host {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
    let controller = UIViewController()

    init() {
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func add(_ view: UIView) {
        controller.view.addSubview(view)
    }
}

/// A view backed by an AVPlayerLayer, as a video creative renders one.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
}

/// A small real PNG.
func testPNG(width: CGFloat = 4, height: CGFloat = 3) -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// A PNG as a data: URI.
func testPNGDataURI() -> String {
    "data:image/png;base64," + testPNG().base64EncodedString()
}

/// Base for the view shell tests: failure capture, fake ad SDKs, manual
/// timers and a captured events queue, all installed in the views'
/// environments, and put back afterwards.
class ViewTestCase: FailureCapturingTestCase {

    var network: FakeAdNetwork!
    var scheduler: ManualScheduler!
    var recorder: EventRecorder!
    var opened: [URL] = []
    var growthCodeZones: [String?] = []
    /// Native auctions the views asked for, answered by hand.
    var nativeFetches: [(request: NativeRequest, done: (BidInfo) -> Void)] = []
    private var savedHouseLoader: SellwildHouseAd.ImageLoader!

    override func setUp() {
        super.setUp()
        network = FakeAdNetwork()
        scheduler = ManualScheduler()
        recorder = EventRecorder()
        opened = []
        growthCodeZones = []
        SellwildAdView.environment = SellwildAdView.Environment(
            events: recorder.client,
            network: network,
            scheduler: scheduler,
            resolveGrowthCode: { [weak self] _, zone in self?.growthCodeZones.append(zone) },
            openURL: { [weak self] url in self?.opened.append(url) }
        )
        nativeFetches = []
        SellwildNativeAdView.environment = SellwildNativeAdView.Environment(
            fetchDemand: { [weak self] request, done in self?.nativeFetches.append((request, done)) },
            imageSession: StubURLProtocol.makeSession()
        )
        savedHouseLoader = SellwildHouseAd.imageLoader
        SellwildHouseAd.imageLoader = SellwildHouseAd.ImageLoader(
            download: { _, completion in completion(.success(testPNG())) },
            directory: { nil }
        )
        SellwildHouseAd.clearMemoryCache()
        SellwildGeoStore.current = nil
    }

    override func tearDown() {
        SellwildAdView.environment = .live
        SellwildNativeAdView.environment = .live
        SellwildHouseAd.imageLoader = savedHouseLoader
        SellwildHouseAd.clearMemoryCache()
        SellwildGeoStore.current = nil
        super.tearDown()
    }

    /// Runs the main queue until `condition` holds or `timeout` passes.
    func spin(timeout: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// Runs the main queue briefly so queued main-thread work runs.
    func drainMain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
