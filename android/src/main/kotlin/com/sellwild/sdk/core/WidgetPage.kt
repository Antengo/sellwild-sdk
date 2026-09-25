package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.SellwildPhoto
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONException
import org.json.JSONObject

/**
 * The page SellwildWidgetView loads, pure: the `<sellwild-widget>` element with the config as
 * attributes, the Prebid.js pre-config script and the bridge script. The WebView widget is
 * deprecated: this is the page it always loaded, except that the bridge script counts the
 * messages it could not post (window.__sellwildBridgeFailures) instead of dropping them in an
 * empty catch.
 */
internal object WidgetPage {
    const val BASE_URL = "https://widget.sellwild.com"

    /**
     * The generic bundle that reads all config from the element's attributes. partner.js
     * loads its own Prebid build: no separate prebid script tag (it would double-load).
     */
    const val SCRIPT_URL = "https://widget.sellwild.com/partner.js"

    /** The full HTML document for [config]; [remote] is its parsed remote config, or null. */
    fun html(config: SellwildConfig, remote: JSONObject?): String {
        val attrs = attributes(config, remote)
        val prebidPreConfig = prebidPreConfig(config)
        return """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: 100%; background: transparent; overflow-x: hidden; }
  </style>
  $prebidPreConfig
</head>
<body>
  <sellwild-widget
    $attrs
  ></sellwild-widget>

  <script>
    (function() {
      function send(type, payload) {
        try {
          SellwildWidgetBridge.postMessage(JSON.stringify(Object.assign({ type: type }, payload || {})));
        } catch(e) {
          // The bridge is the page's only way out, so this cannot be reported.
          // Count it where a debugger can read it (as the React Native page does).
          window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1;
        }
      }
      // partner/index.tsx calls window.open() on listing tap — intercept ALL
      // calls. Listings link to external sites (eBay, Amazon, dealer sites, etc.)
      // so we can't filter by domain. The widget only uses window.open for listings.
      var _open = window.open;
      window.open = function(url) {
        if (url) {
          send('LISTING_CLICK', { url: url });
          return null;
        }
        return _open.apply(window, arguments);
      };
      document.addEventListener('DOMContentLoaded', function() {
        setTimeout(function() { send('WIDGET_LOADED'); }, 600);
      });
      window.addEventListener('error', function(e) {
        send('ERROR', { message: e.message || 'Widget load error' });
      });
    })();
  </script>

  <script async src="$SCRIPT_URL"></script>
</body>
</html>"""
    }

    /**
     * The config as element attributes, one per line. The widget reads them with
     * withCustomizationsFromElement() (names in any case); bidder objects are JSON its
     * parseValue() parses. Every key of [remote] not already emitted is passed through as
     * `lower-kebab-case="value"`, which is how new bidders and remote settings reach the widget
     * without an SDK release. Values are not escaped beyond `"` in JSON (unchanged behavior).
     */
    fun attributes(config: SellwildConfig, remote: JSONObject?): String {
        val parts = mutableListOf<String>()

        fun add(name: String, value: String?) {
            if (!value.isNullOrEmpty()) parts.add("$name=\"$value\"")
        }
        fun addBool(name: String, value: Boolean) {
            if (value) parts.add("$name=\"true\"")
        }
        fun addInt(name: String, value: Int) {
            if (value != 0) parts.add("$name=\"$value\"")
        }
        // A data class's toString() is not JSON, so bidder configs are built field by field.
        fun addJson(name: String, json: JSONObject?) {
            if (json == null) return
            parts.add("$name=\"${json.toString().replace("\"", "&quot;")}\"")
        }

        add("partner-code", config.partnerCode)
        add("listings", config.effectiveListingsUrl)
        // Remote customization fetch off (see RN htmlBuilder.ts).
        parts.add("customize=\"false\"")
        // Ad system selection is required (see RN htmlBuilder.ts).
        add("ad-type", config.adType ?: "PrebidOnly")
        add("gam-tag", config.gamTag)
        add("gpt-proxy-url", config.gptProxyUrl)
        addBool("disable-gpt", config.disableGpt)
        add("banner-zid", config.bannerZid)
        add("bottom-banner-zid", config.bottomBannerZid)
        add("mobile-banner-zid", config.mobileBannerZid)
        // Empties filtered: the widget's parser keeps empty strings after a split.
        config.mobileZids.filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }
            ?.let { add("mobile-zid", it.joinToString(",")) }
        addBool("hide-banner-top", config.hideBannerTop)
        addBool("hide-banner-bottom", config.hideBannerBottom)
        addInt("ad-refresh-max", config.adRefreshMax)
        addInt("ad-refresh-max-mobile", config.adRefreshMaxMobile)
        if (config.adRefreshIntervalMs > 0) parts.add("ad-refresh-interval=\"${config.adRefreshIntervalMs}\"")
        addBool("boltive", config.boltive)
        add("boltive-client-id", config.boltiveClientId)
        addBool("lotame", config.lotame)
        add("title", config.title)
        add("link-text", config.linkText)
        addInt("font-size", config.fontSize)
        add("font-color", config.fontColor)
        add("price-color", config.priceColor)
        add("price-font-color", config.priceFontColor)
        if (config.colors.isNotEmpty()) add("colors", config.colors.joinToString(","))
        addBool("debug", config.debug)

        addJson("ix", config.ix?.let { ix ->
            JSONObject().apply {
                put("siteIdM", ix.siteIdM)
                put("siteIdD", ix.siteIdD)
                if (ix.disabled) put("disabled", true)
            }
        })
        addJson("openx", config.openx?.let { ox ->
            JSONObject().apply {
                put("delDomain", ox.delDomain)
                put("unitM", ox.unitM)
                put("unitD", ox.unitD)
                if (ox.disabled) put("disabled", true)
            }
        })
        addJson("pubmatic", config.pubmatic?.let { pm ->
            JSONObject().apply {
                put("pubIdM", pm.pubIdM)
                put("adSlotM", pm.adSlotM)
                put("adSlotD", pm.adSlotD)
                if (pm.disabled) put("disabled", true)
            }
        })
        addJson("appnexus", config.appnexus?.let { an ->
            JSONObject().apply {
                put("placementIdM", an.placementIdM)
                put("placementIdD", an.placementIdD)
                if (an.disabled) put("disabled", true)
            }
        })

        addBool("enable-interstitial", config.enableInterstitial)
        addBool("enable-fullscreen-video", config.enableFullscreenVideo)
        addInt("interstitials-per-session", config.interstitialsPerSession)
        addInt("video-takeovers-per-session", config.videoTakeoversPerSession)

        if (remote != null) {
            // Keys the typed serializer above already emitted are skipped (the widget's
            // attribute names are case-insensitive, so CONSTANT_CASE maps onto them).
            val emitted = parts.map { it.substringBefore("=") }.toMutableSet()
            for (key in remote.keys()) {
                val attr = key.lowercase().replace("_", "-")
                if (!emitted.add(attr)) continue
                parts.add("$attr=\"${remote.get(key).toString().replace("\"", "&quot;")}\"")
            }
        }

        return parts.joinToString("\n    ")
    }

    /**
     * The Prebid.js pre-config script, queued before prebid.js loads (pbjs.que). It declares
     * in-app inventory (ortb2.app) so DSPs bid on app traffic, turns iframe user syncs off (no
     * third-party cookies in a WebView), and with a typed Prebid Server config routes bidders
     * through it (s2sConfig).
     */
    fun prebidPreConfig(config: SellwildConfig): String {
        val fields = mutableListOf("\"publisher\": {\"id\": \"${config.partnerCode}\"}")
        config.appBundleId?.let { fields.add("\"bundle\": \"$it\"") }
        config.appStoreUrl?.let { fields.add("\"storeurl\": \"$it\"") }
        val ortb2App = "{${fields.joinToString(", ")}}"

        val ps = config.prebidServer
        val s2sConfigBlock = if (ps == null) {
            ""
        } else {
            val bidderList = ps.bidders.joinToString(", ") { "\"$it\"" }
            val sync = ps.syncEndpoint
            val syncLine = if (sync == null) "" else ", \"syncEndpoint\": {\"p1Consent\": \"$sync\", \"noP1Consent\": \"$sync\"}"
            """,
                // Route all bidder calls through Prebid Server (S2S mode).
                s2sConfig: {
                  "accountId": "${ps.accountId}",
                  "bidders": [$bidderList],
                  "timeout": ${ps.timeout},
                  "adapter": "prebidServer",
                  "endpoint": {"p1Consent": "${ps.endpoint}", "noP1Consent": "${ps.endpoint}"}$syncLine
                }"""
        }

        val debugFlag = if (config.debug) ", \"debug\": true" else ""
        return """
          <script>
            window.pbjs = window.pbjs || {};
            window.pbjs.que = window.pbjs.que || [];
            window.pbjs.que.push(function() {
              window.pbjs.setConfig({
                ortb2: { app: $ortb2App },
                userSync: {
                  filterSettings: { iframe: { bidders: '*', filter: 'exclude' } },
                  syncDelay: 5000
                }$s2sConfigBlock$debugFlag
              });
            });
          </script>
        """.trimIndent()
    }

    /**
     * Whether a WebView load error for [url] blanks the widget, and so is reported: the page
     * itself (the main frame) or the widget bundle. Other subresources (listing images, ad
     * creatives) fail routinely and the widget copes.
     */
    fun isWidgetResource(url: String?, isMainFrame: Boolean): Boolean = isMainFrame || url == SCRIPT_URL

    /**
     * The WebView data directory suffix for a process other than the app's main one (API 28+):
     * the process name with the package prefix and `:` removed. Null on API 27 and below, and
     * for the main process. [processName] is asked only on API 28+, where it exists.
     */
    fun dataDirectorySuffix(sdkInt: Int, packageName: String, processName: () -> String?): String? {
        if (sdkInt < API_28) return null
        val process = processName() ?: packageName
        if (process == packageName) return null
        return process.replace(packageName, "").trimStart(':')
    }

    private const val API_28 = 28
}

/** A message the widget page posted to the native bridge. */
internal sealed class BridgeMessage {
    object Loaded : BridgeMessage()

    class ListingClick(val listing: SellwildListing) : BridgeMessage()

    class AdImpression(val zoneId: String) : BridgeMessage()

    class Error(val message: String) : BridgeMessage()
}

/** Decodes what the widget page posts to SellwildWidgetBridge.postMessage, pure. */
internal object WidgetBridge {

    /**
     * The message in [json], or null with the issue: text that is not JSON is
     * bridge.message.parse, a listing whose photos are not objects is bridge.message.invalid,
     * and a type the SDK does not know is bridge.message.unsupported.
     */
    fun decode(json: String): Resolved<BridgeMessage?> {
        val obj = try {
            JSONObject(json)
        } catch (e: JSONException) {
            return failed(SellwildFailureCode.BRIDGE_MESSAGE_PARSE, "bridge message is not JSON", e)
        }
        return when (val type = obj.optString("type")) {
            "WIDGET_LOADED" -> Resolved(BridgeMessage.Loaded)
            "LISTING_CLICK" -> try {
                Resolved(BridgeMessage.ListingClick(listingOf(obj)))
            } catch (e: JSONException) {
                failed(SellwildFailureCode.BRIDGE_MESSAGE_INVALID, "LISTING_CLICK listing is not valid", e)
            }
            "AD_IMPRESSION" -> Resolved(BridgeMessage.AdImpression(obj.optString("zoneId")))
            "ERROR" -> Resolved(BridgeMessage.Error(obj.optString("message")))
            else -> failed(SellwildFailureCode.BRIDGE_MESSAGE_UNSUPPORTED, "unsupported bridge message type: $type")
        }
    }

    /**
     * The tapped listing: the message's `listing` object when there is one, else a stub
     * carrying only the URL (window.open gives the page nothing more).
     */
    private fun listingOf(obj: JSONObject): SellwildListing {
        val listing = obj.optJSONObject("listing")
        return if (listing != null) {
            parseListing(listing)
        } else {
            SellwildListing(id = "", status = "active", title = "", url = obj.optString("url").ifEmpty { null })
        }
    }

    /** A listing from the page's partial listing object. A photo that is not an object throws. */
    fun parseListing(json: JSONObject): SellwildListing {
        val photosArray = json.optJSONArray("photos")
        val photos = if (photosArray != null) {
            (0 until photosArray.length()).map { i ->
                val p = photosArray.getJSONObject(i)
                SellwildPhoto(url = p.optString("url"), thumbUrl = p.optString("thumbUrl"))
            }
        } else {
            emptyList()
        }
        return SellwildListing(
            id = json.optString("id"),
            status = json.optString("status"),
            title = json.optString("title"),
            url = json.optString("url").ifEmpty { null },
            price = json.optString("price").ifEmpty { null },
            currency = json.optString("currency").ifEmpty { null },
            photos = photos,
        )
    }

    private fun failed(code: String, message: String, error: Throwable? = null): Resolved<BridgeMessage?> =
        Resolved(
            null,
            listOf(Issue(code, SellwildFailureComponent.BRIDGE, SellwildFailureSeverity.WARN, message = message, error = error)),
        )
}
