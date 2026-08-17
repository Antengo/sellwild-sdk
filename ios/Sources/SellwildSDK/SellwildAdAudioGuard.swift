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
//   • Only reaches media in the WebView's MAIN frame. A creative whose media
//     lives in a cross-origin <iframe> is walled off by the same-origin policy
//     (this is exactly why the vendors inject at WebView-creation, which needs a
//     fork change). Muted video autoplay still shows; only sound is targeted.
//   • Only covers WebViews inside our own view tree. GAM/AdX creatives rendered
//     in Google's own container are out of reach here.
//   • We evaluate AFTER load + a few short retries, so there can be a brief blip
//     of sound before the shim lands.
//
// Toggle: MOBILE_AD_MUTE_AUTOPLAY (default true) — set false to disable.

import UIKit
import WebKit

enum SellwildAdAudioGuard {

    /// Whether the audio guard runs. Defaults to `true`; set
    /// `MOBILE_AD_MUTE_AUTOPLAY: false` in remote config to disable.
    static func isEnabled(remoteValues: [String: Any]?) -> Bool {
        guard let raw = remoteValues?["MOBILE_AD_MUTE_AUTOPLAY"] else { return true }
        switch raw {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return !["0", "false", "no", "off"].contains(s.lowercased())
        default: return true
        }
    }

    /// Retry offsets (seconds) after a creative renders — autoplay often starts
    /// slightly after load (viewability trigger), so re-apply a few times.
    static let retryDelays: [TimeInterval] = [0, 0.4, 1.2, 2.5]

    /// Apply the mute shim to every WKWebView inside `container`, now and on a
    /// few short retries. No-op when disabled or when there's no WebView yet.
    static func apply(to container: UIView, remoteValues: [String: Any]?) {
        guard isEnabled(remoteValues: remoteValues) else { return }
        for delay in retryDelays {
            if delay == 0 {
                muteWebViews(in: container)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak container] in
                    guard let container else { return }
                    muteWebViews(in: container)
                }
            }
        }
    }

    /// Evaluate the mute shim in each WKWebView found under `root`.
    private static func muteWebViews(in root: UIView) {
        for webView in webViews(in: root) {
            webView.evaluateJavaScript(muteScript, completionHandler: nil)
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
    static let muteScript: String = """
    (function(){
      try {
        var mute = function(m){ try { m.muted = true; m.volume = 0; m.setAttribute('muted',''); } catch(e){} };
        var muteAll = function(){
          try {
            var els = document.querySelectorAll('video, audio');
            for (var i = 0; i < els.length; i++) { mute(els[i]); }
          } catch(e){}
        };
        if (!window.__swAudioGuard) {
          window.__swAudioGuard = true;
          var proto = window.HTMLMediaElement && HTMLMediaElement.prototype;
          if (proto && proto.play) {
            var origPlay = proto.play;
            proto.play = function(){ try { this.muted = true; this.volume = 0; } catch(e){} return origPlay.apply(this, arguments); };
          }
          try {
            var mo = new MutationObserver(muteAll);
            mo.observe(document.documentElement || document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src','autoplay','muted'] });
          } catch(e){}
        }
        muteAll();
      } catch(e){}
    })();
    """
}
