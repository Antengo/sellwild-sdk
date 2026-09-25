package com.sellwild.sample

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildSDK
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * What the sample passes to the SDK. It is the same on every platform's sample app,
 * so the e2e flows see the same app.
 */
object SampleSettings {
    /** Sellwild's own partner code. Never use a real partner's code here. */
    const val PARTNER_CODE = "sellwild"

    /**
     * There is no app config for this slug on the CDN (it answers 403). So `configure`
     * keeps the SDK's built-in config and Google test ad units, and reports
     * `config.fetch.http` once a launch. That is expected.
     */
    const val SLUG = "sellwild-sample"

    /** Sellwild's own listings feed, passed as the config's `listingsUrl`. */
    const val LISTINGS_URL = "https://cache.sellwild.com/listings-img-data-sm-avif-fandom"

    /** Feed rows: L = listing card, G = 300x250 ad, B = 320x50 banner. */
    const val FEED_SCHEDULE = "LGLLBLLGLL"
    const val MREC_ZONE = "sellwild-sample-mrec"
    const val BANNER_ZONE = "sellwild-sample-banner"
    const val NATIVE_ZONE = "sellwild-sample-native"
}

/** Where the config came from: the CDN, or the SDK's built-in fallback. */
enum class ConfigSource(val label: String) {
    Remote("remote"),
    Fallback("fallback"),
}

/** configure() keeps the CDN payload in remoteJson; the fallback has none. */
val SellwildConfig.source: ConfigSource
    get() = if (remoteJson == null) ConfigSource.Fallback else ConfigSource.Remote

/** Runs `SellwildSDK.configure` once a launch and holds the result. */
class SampleViewModel(app: Application) : AndroidViewModel(app) {
    private val configState = MutableStateFlow<SellwildConfig?>(null)
    val config: StateFlow<SellwildConfig?> = configState.asStateFlow()

    init {
        viewModelScope.launch {
            val config = SellwildSDK.configure(
                partnerCode = SampleSettings.PARTNER_CODE,
                slug = SampleSettings.SLUG,
            ) { config ->
                // App-controlled values. CDN values win where the CDN has them.
                config.copy(
                    listingsUrl = SampleSettings.LISTINGS_URL,
                    appBundleId = app.packageName,
                    debug = true,
                    col1 = config.col1?.takeIf { it.isNotEmpty() } ?: SampleSettings.FEED_SCHEDULE,
                    title = config.title ?: "Sellwild Sample",
                    mobileZids = config.mobileZids.ifEmpty { listOf(SampleSettings.MREC_ZONE) },
                    mobileBannerZid = config.mobileBannerZid?.takeIf { it.isNotEmpty() } ?: SampleSettings.BANNER_ZONE,
                )
            }
            // Optional: starts Prebid Mobile and Google Mobile Ads now, so the first ad
            // does not wait for them.
            SellwildSDK.prewarm(getApplication(), config)
            configState.update { config }
        }
    }
}
