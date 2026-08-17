// SellwildAdAudioGuard.kt — best-effort, client-side mute of auto-playing
// ad-creative audio, entirely on the SDK surface (no Prebid-fork change).
//
// A rendered banner/MRAID creative can autoplay video/audio with sound. The
// underlying Prebid/GAM WebView is created inside the ad SDK (we don't own its
// settings), so we can't set `setMediaPlaybackRequiresUserGesture(true)` or
// inject a document-start script the way an ad-quality vendor (Boltive, etc.)
// would. Instead we reach into the WebView(s) that end up inside OUR ad
// container and evaluate a small mute shim: patch `HTMLMediaElement.play` to
// force-mute, mute any existing `<video>/<audio>`, and keep muting new media
// via a MutationObserver.
//
// BEST-EFFORT — known limits (documented on purpose):
//   • Only reaches media in the WebView's MAIN frame. A creative whose media
//     lives in a cross-origin <iframe> is walled off by the same-origin policy
//     (this is why the vendors inject at WebView-creation, which needs a fork
//     change). Muted video autoplay still shows; only sound is targeted.
//   • Only covers WebViews inside our own view tree. GAM/AdX creatives rendered
//     in Google's own container are out of reach here.
//   • We evaluate AFTER load + a few short retries, so there can be a brief blip
//     of sound before the shim lands.
//
// Toggle: MOBILE_AD_MUTE_AUTOPLAY (default true) — set false to disable.

package com.sellwild.sdk

import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import org.json.JSONObject
import java.lang.ref.WeakReference

internal object SellwildAdAudioGuard {

    /** Whether the audio guard runs. Defaults to true; set
     *  `MOBILE_AD_MUTE_AUTOPLAY: false` in remote config to disable. */
    fun isEnabled(remoteJson: String?): Boolean {
        val obj = remoteJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return true
        if (!obj.has("MOBILE_AD_MUTE_AUTOPLAY") || obj.isNull("MOBILE_AD_MUTE_AUTOPLAY")) return true
        return when (val v = obj.get("MOBILE_AD_MUTE_AUTOPLAY")) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> v.lowercase() !in setOf("0", "false", "no", "off")
            else -> true
        }
    }

    // Autoplay often starts slightly after load (viewability trigger), so
    // re-apply a few times.
    private val retryDelaysMs = longArrayOf(0L, 400L, 1200L, 2500L)

    /** Apply the mute shim to every WebView inside [container], now and on a few
     *  short retries. No-op when disabled or when there's no WebView yet. */
    fun apply(container: View, remoteJson: String?) {
        if (!isEnabled(remoteJson)) return
        val main = Handler(Looper.getMainLooper())
        val ref = WeakReference(container)
        for (delay in retryDelaysMs) {
            if (delay == 0L) {
                muteWebViews(container)
            } else {
                main.postDelayed({ ref.get()?.let { muteWebViews(it) } }, delay)
            }
        }
    }

    private fun muteWebViews(root: View) {
        for (wv in webViews(root)) {
            runCatching { wv.evaluateJavascript(MUTE_SCRIPT, null) }
        }
    }

    /** Depth-first collect every [WebView] in the view subtree rooted at [root]
     *  (including [root]). `internal` so it's unit-testable. */
    fun webViews(root: View): List<WebView> {
        val out = mutableListOf<WebView>()
        collect(root, out)
        return out
    }

    private fun collect(view: View, out: MutableList<WebView>) {
        if (view is WebView) out.add(view)
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) collect(view.getChildAt(i), out)
        }
    }

    /** JS mute shim, run in the WebView's main frame. Idempotent (guards against
     *  re-install), patches `HTMLMediaElement.play` to force-mute, mutes existing
     *  media, and installs a MutationObserver to mute media added later. */
    const val MUTE_SCRIPT: String = """
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
