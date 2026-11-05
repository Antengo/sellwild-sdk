// SellwildAdAudioGuard.swift — best-effort, client-side mute of auto-playing
// ad-creative audio, entirely on the SDK surface (no Prebid-fork change).
//
// A rendered banner/MRAID creative can autoplay video/audio with sound. The
// underlying Prebid/GAM WebView is created inside the ad SDK (we don't own its
// configuration), so we can't set `mediaTypesRequiringUserActionForPlayback` or
// inject a document-start script the way an ad-quality vendor (Boltive, etc.)
// would. Instead we reach into the WKWebView(s) that end up inside OUR ad
// container and evaluate a small mute shim: patch `HTMLMediaElement.play` to
// force-mute, mute any existing `<video>/<audio>`, and keep muting new media via
// a MutationObserver.
//
// BEST-EFFORT — known limits (documented on purpose):
//   • The `evaluateJavaScript` pass only reaches media in the WebView's MAIN
//     frame — a creative whose media lives in a cross-origin <iframe> is walled
//     off by the same-origin policy. To narrow this gap WITHOUT a fork change,
//     `apply` also attaches a `WKUserScript` (`forMainFrameOnly: false`,
//     `.atDocumentStart`) to the WebView's OWN `configuration.userContentController`
//     — a fully public property on any WKWebView we can already reach, no fork
//     access needed. Per-frame `WKUserScript`s run on THAT frame's own
//     navigation, so this reaches an iframe that loads/reloads AFTER we attach
//     it (common for viewability-triggered creatives) — but not an iframe
//     that's already fully loaded by the time we find the WebView. True,
//     complete coverage still needs the fork to attach at WebView-CREATION
//     time, before any navigation starts (a fork change).
//   • Only covers WebViews inside our own view tree. GAM/AdX creatives rendered
//     in Google's own container are out of reach here.
//   • We evaluate AFTER load + a few short retries, so there can be a brief blip
//     of sound before the shim lands.
//
// Toggle: MOBILE_AD_MUTE_AUTOPLAY (default true) — set false to disable.
//
// Failures: an evaluation that fails, and errors the shim catches inside the
// page (it counts them and returns the count), are reported as
// `ad.audio_guard.exception`.

import UIKit
import WebKit

enum SellwildAdAudioGuard {

    /// Whether the audio guard runs. Defaults to `true`; set
    /// `MOBILE_AD_MUTE_AUTOPLAY: false` in remote config to disable.
    /// Same coercion as every kill switch (FAILURES.md 5.3; the app-config
    /// schema's flag type trims text).
    static func isEnabled(remoteValues: [String: Any]?) -> Bool {
        SellwildFailuresCore.coerceFlag(remoteValues?["MOBILE_AD_MUTE_AUTOPLAY"])
    }

    /// Retry offsets (seconds) after a creative renders — autoplay often starts
    /// slightly after load (viewability trigger), so re-apply a few times.
    static let retryDelays: [TimeInterval] = [0, 0.4, 1.2, 2.5]

    /// Runs a script in a WebView and hands back its result or error. A seam:
    /// a test passes its own so `apply` runs without a WebContent process.
    typealias Evaluator = (WKWebView, String, @escaping (Any?, Error?) -> Void) -> Void

    /// The real evaluator: WebKit's `evaluateJavaScript`.
    static func evaluateInPage(_ webView: WKWebView, _ script: String, _ done: @escaping (Any?, Error?) -> Void) {
        webView.evaluateJavaScript(script) { result, error in done(result, error) }
    }

    /// Apply the mute shim to every WKWebView inside `container`, now and on a
    /// few short retries. No-op when disabled or when there's no WebView yet.
    static func apply(to container: UIView, remoteValues: [String: Any]?, delays: [TimeInterval] = retryDelays,
                      evaluate: @escaping Evaluator = evaluateInPage) {
        guard isEnabled(remoteValues: remoteValues) else { return }
        // One-time (not per-retry) per-frame injection — see the file header
        // for why this reaches cross-origin iframes the evaluateJavaScript
        // pass below cannot.
        installUserScripts(in: container)
        for delay in delays {
            if delay == 0 {
                muteWebViews(in: container, evaluate: evaluate)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak container] in
                    guard let container else { return }
                    muteWebViews(in: container, evaluate: evaluate)
                }
            }
        }
    }

    /// Marks a `WKUserContentController` we've already injected into, so a
    /// repeat `apply()` call (a refresh reusing the same WebView) doesn't stack
    /// duplicate copies of the same script on every render.
    private static var injectedKey: UInt8 = 0

    /// Attach `muteScript` as a `WKUserScript` to every WebView's OWN
    /// configuration, `forMainFrameOnly: false` so it runs in every frame
    /// (including cross-origin iframes) on THAT frame's own navigation —
    /// sidestepping the same-origin restriction `evaluateJavaScript` hits.
    /// Idempotent per WebView (see `injectedKey`); does nothing for a frame
    /// that's already finished loading before we attach.
    private static func installUserScripts(in root: UIView) {
        for webView in webViews(in: root) {
            let controller = webView.configuration.userContentController
            if objc_getAssociatedObject(controller, &injectedKey) as? Bool == true { continue }
            objc_setAssociatedObject(controller, &injectedKey, true, .OBJC_ASSOCIATION_RETAIN)
            let script = WKUserScript(
                source: muteScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            controller.addUserScript(script)
        }
    }

    /// Evaluate the mute shim in each WKWebView found under `root`.
    private static func muteWebViews(in root: UIView, evaluate: Evaluator) {
        for webView in webViews(in: root) {
            evaluate(webView, muteScript) { result, error in
                report(result: result, error: error)
            }
        }
    }

    /// Reports one evaluation of the shim: the evaluation failed, or the shim
    /// caught errors in the page (its result is how many).
    static func report(result: Any?, error: Error?) {
        if let error {
            SellwildFailures.log(code: .adAudioGuardException, component: .banner, severity: .warn, error: error,
                                 message: "mute shim evaluation failed")
        } else if let caught = (result as? NSNumber)?.intValue, caught > 0 {
            SellwildFailures.log(code: .adAudioGuardException, component: .banner, severity: .warn,
                                 message: "mute shim caught errors in the ad page")
        }
    }

    /// Depth-first collect every `WKWebView` in the view subtree rooted at
    /// `root` (including `root`). `internal` so it's unit-testable.
    static func webViews(in root: UIView) -> [WKWebView] {
        var found: [WKWebView] = []
        if let wv = root as? WKWebView { found.append(wv) }
        for sub in root.subviews {
            found.append(contentsOf: webViews(in: sub))
        }
        return found
    }

    /// JS mute shim, run in the WebView's main frame. Idempotent (guards against
    /// re-install), patches `HTMLMediaElement.play` to force-mute, mutes existing
    /// media, and installs a MutationObserver to mute media added later.
    ///
    /// The page cannot report a failure itself, so every catch counts the
    /// error in `window.__swAudioGuardErrors`. The shim returns that count
    /// and resets it; `report(result:error:)` reports a count above zero.
    static let muteScript: String = """
    (function(){
      var fail = function(){ window.__swAudioGuardErrors = (window.__swAudioGuardErrors | 0) + 1; };
      try {
        var mute = function(m){ try { m.muted = true; m.volume = 0; m.setAttribute('muted',''); } catch(e){ fail(); } };
        var muteAll = function(){
          try {
            var els = document.querySelectorAll('video, audio');
            for (var i = 0; i < els.length; i++) { mute(els[i]); }
          } catch(e){ fail(); }
        };
        if (!window.__swAudioGuard) {
          window.__swAudioGuard = true;
          var proto = window.HTMLMediaElement && HTMLMediaElement.prototype;
          if (proto && proto.play) {
            var origPlay = proto.play;
            proto.play = function(){ try { this.muted = true; this.volume = 0; } catch(e){ fail(); } return origPlay.apply(this, arguments); };
          }
          try {
            var mo = new MutationObserver(muteAll);
            mo.observe(document.documentElement || document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src','autoplay','muted'] });
          } catch(e){ fail(); }
        }
        muteAll();
      } catch(e){ fail(); }
      var caught = window.__swAudioGuardErrors | 0;
      window.__swAudioGuardErrors = 0;
      return caught;
    })();
    """
}
