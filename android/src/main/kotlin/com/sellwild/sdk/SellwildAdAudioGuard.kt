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
import com.sellwild.sdk.core.RemoteValues
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures
import java.lang.ref.WeakReference
import java.util.Collections
import java.util.WeakHashMap

internal object SellwildAdAudioGuard {

    /** Whether the audio guard runs. Defaults to true; set
     *  `MOBILE_AD_MUTE_AUTOPLAY: false` in remote config to disable. */
    fun isEnabled(remoteJson: String?): Boolean =
        RemoteValues.isNotOff(RemoteValues.optAny(remoteObject(remoteJson), "MOBILE_AD_MUTE_AUTOPLAY"))

    // Autoplay often starts slightly after load (viewability trigger), so
    // re-apply a few times.
    private val retryDelaysMs = longArrayOf(0L, 400L, 1200L, 2500L)

    /** Apply the mute shim to every WebView inside [container], now and on a few
     *  short retries. No-op when disabled or when there's no WebView yet. */
    fun apply(container: View, remoteJson: String?) {
        if (!isEnabled(remoteJson)) return
        val main = Handler(Looper.getMainLooper())
        val ref = WeakReference(container)
        val run = Run()
        for (delay in retryDelaysMs) {
            if (delay == 0L) {
                muteWebViews(container, run)
            } else {
                main.postDelayed({ muteIfAlive(ref, run) }, delay)
            }
        }
    }

    /**
     * What one [apply] already saw, so each WebView is reported once per apply, not on every
     * retry (FAILURES.md 9, log once): a WebView that threw is dead and is not tried again,
     * and a shim that threw in a page is reported for that page once. Weak, so a destroyed ad
     * view's WebViews are not kept. Used on the main thread only.
     */
    internal class Run {
        val threw: MutableSet<WebView> = Collections.newSetFromMap(WeakHashMap())
        val shimReported: MutableSet<WebView> = Collections.newSetFromMap(WeakHashMap())
    }

    /** A retry: the container may be gone by then (its ad view was destroyed). */
    internal fun muteIfAlive(ref: WeakReference<View>, run: Run) {
        ref.get()?.let { muteWebViews(it, run) }
    }

    private fun muteWebViews(root: View, run: Run) {
        for (wv in webViews(root)) {
            if (wv in run.threw) continue
            // A destroyed WebView, or a call off its thread, throws: that one stays unmuted.
            runCatching { wv.evaluateJavascript(MUTE_SCRIPT) { result -> reportShimErrors(wv, result, run) } }
                .onFailure { e ->
                    run.threw += wv
                    SellwildFailures.log(
                        code = SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION,
                        component = SellwildFailureComponent.BANNER,
                        severity = SellwildFailureSeverity.WARN,
                        error = e,
                    )
                }
        }
    }

    // The shim counts what threw inside the page (a media element that refused to mute,
    // an observer that could not attach) and returns the count, since the page itself
    // cannot report. A page that throws on one run throws on the next: once per apply.
    private fun reportShimErrors(wv: WebView, result: String?, run: Run) {
        if (shimErrors(result) == 0 || !run.shimReported.add(wv)) return
        SellwildFailures.log(
            code = SellwildFailureCode.AD_AUDIO_GUARD_EXCEPTION,
            component = SellwildFailureComponent.BANNER,
            severity = SellwildFailureSeverity.WARN,
            message = "the mute shim threw in the page",
        )
    }

    /**
     * How many times the shim threw since its last run, from evaluateJavascript's result:
     * the JSON of the script's return value ("2"), or "null" when it did not finish.
     */
    internal fun shimErrors(result: String?): Int = result?.toDoubleOrNull()?.toInt() ?: 0

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
     *  media, and installs a MutationObserver to mute media added later. Every catch
     *  counts into `window.__swAudioGuardErrors`, and each run returns the count since
     *  the last one (then clears it) for [reportShimErrors]. */
    const val MUTE_SCRIPT: String = """
    (function(){
      var fail = function(){ window.__swAudioGuardErrors = (window.__swAudioGuardErrors || 0) + 1; };
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
      var errors = window.__swAudioGuardErrors || 0;
      window.__swAudioGuardErrors = 0;
      return errors;
    })();
    """
}
