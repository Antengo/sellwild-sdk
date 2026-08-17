import XCTest
import UIKit
import WebKit
@testable import SellwildSDK

/// Unit tests for the best-effort ad audio guard: the remote-config gate, the
/// WKWebView subtree traversal, and the mute-shim contents. (The actual muting
/// needs a live creative, so it's verified on-device, not here.)
final class SellwildAdAudioGuardTests: XCTestCase {

    // MARK: isEnabled

    func testEnabledByDefault() {
        XCTAssertTrue(SellwildAdAudioGuard.isEnabled(remoteValues: nil))
        XCTAssertTrue(SellwildAdAudioGuard.isEnabled(remoteValues: ["CODE": "weatherbug"]))
    }

    func testDisableViaRemoteFlag() {
        XCTAssertFalse(SellwildAdAudioGuard.isEnabled(remoteValues: ["MOBILE_AD_MUTE_AUTOPLAY": false]))
        XCTAssertFalse(SellwildAdAudioGuard.isEnabled(remoteValues: ["MOBILE_AD_MUTE_AUTOPLAY": "off"]))
        XCTAssertFalse(SellwildAdAudioGuard.isEnabled(remoteValues: ["MOBILE_AD_MUTE_AUTOPLAY": 0]))
        XCTAssertTrue(SellwildAdAudioGuard.isEnabled(remoteValues: ["MOBILE_AD_MUTE_AUTOPLAY": true]))
    }

    // MARK: webViews(in:)

    func testFindsNestedWebViews() {
        let root = UIView()
        let mid = UIView()
        root.addSubview(mid)
        let deepWebView = WKWebView()
        mid.addSubview(deepWebView)
        let siblingWebView = WKWebView()
        root.addSubview(siblingWebView)
        // A non-webview leaf shouldn't be collected.
        root.addSubview(UILabel())

        let found = SellwildAdAudioGuard.webViews(in: root)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains(deepWebView))
        XCTAssertTrue(found.contains(siblingWebView))
    }

    func testRootItselfIsIncludedWhenItIsAWebView() {
        let webView = WKWebView()
        XCTAssertEqual(SellwildAdAudioGuard.webViews(in: webView).count, 1)
    }

    func testNoWebViewsReturnsEmpty() {
        let root = UIView()
        root.addSubview(UIView())
        root.addSubview(UILabel())
        XCTAssertTrue(SellwildAdAudioGuard.webViews(in: root).isEmpty)
    }

    // MARK: mute shim

    func testMuteScriptForcesMuteAndObservesMedia() {
        let js = SellwildAdAudioGuard.muteScript
        XCTAssertTrue(js.contains("HTMLMediaElement"))
        XCTAssertTrue(js.contains("muted = true"))
        XCTAssertTrue(js.contains("MutationObserver"))
        XCTAssertTrue(js.contains("__swAudioGuard"))   // idempotency guard
        XCTAssertTrue(js.contains("video, audio"))
    }
}
