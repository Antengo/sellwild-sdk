package com.sellwild.sample

import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.sellwild.sdk.AdSize
import com.sellwild.sdk.SellwildAdView
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildNativeAdView
import kotlin.math.roundToInt

private val BANNER = AdSlotSpec(
    title = "Banner 320x50",
    detail = "SellwildAdView, AdSize.BANNER_320x50",
    width = 320,
    height = 50,
    id = SampleIds.AD_BANNER,
    sizeId = SampleIds.AD_BANNER_SIZE,
)
private val MREC = AdSlotSpec(
    title = "MREC 300x250",
    detail = "SellwildAdView, AdSize.MREC_300x250",
    width = 300,
    height = 250,
    id = SampleIds.AD_MREC,
    sizeId = SampleIds.AD_MREC_SIZE,
)
private val NATIVE = AdSlotSpec(
    title = "Native ad",
    detail = "SellwildNativeAdView: Prebid native assets in a native template",
    width = 300,
    height = 250,
    id = SampleIds.AD_NATIVE,
    sizeId = SampleIds.AD_NATIVE_SIZE,
)

/**
 * Ads: each native ad surface on its own. Test ads may not fill; each slot keeps its
 * size either way, and the label under it shows the measured size.
 */
@Composable
fun AdsScreen(config: SellwildConfig) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        ScreenHeader("Ads", "Native Prebid Mobile + GAM. No WebView in the ad path.")
        AdSlot(BANNER) { onStatus -> BannerAd(config, AdSize.BANNER_320x50, SampleSettings.BANNER_ZONE, onStatus) }
        AdSlot(MREC) { onStatus -> BannerAd(config, AdSize.MREC_300x250, SampleSettings.MREC_ZONE, onStatus) }
        AdSlot(NATIVE) { onStatus -> NativeAd(config, SampleSettings.NATIVE_ZONE, NATIVE.height, onStatus) }
        Column(Modifier.padding(horizontal = 16.dp)) {
            Text("House ad", style = MaterialTheme.typography.titleMedium)
            Text(
                "Not public on Android. House backfill runs inside SellwildAdView when a slot does not fill.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** A slot at its fixed size, its measured size (dp) and the ad's last status. */
@Composable
fun AdSlot(spec: AdSlotSpec, ad: @Composable (onStatus: (String) -> Unit) -> Unit) {
    var status by remember { mutableStateOf("Waiting for an ad") }
    var measured by remember { mutableStateOf(IntSize.Zero) }
    val density = LocalDensity.current
    val size = with(density) {
        "${measured.width.toDp().value.roundToInt()}x${measured.height.toDp().value.roundToInt()}"
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(spec.title, style = MaterialTheme.typography.titleMedium)
        Text(
            spec.detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Box(
            Modifier
                .align(Alignment.CenterHorizontally)
                .size(spec.width.dp, spec.height.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .onSizeChanged { measured = it }
                .testTag(spec.id),
        ) {
            ad { status = it }
        }
        Text(
            size,
            Modifier.align(Alignment.CenterHorizontally).testTag(spec.sizeId),
            style = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Monospace),
        )
        Text(
            status,
            Modifier.align(Alignment.CenterHorizontally),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** `SellwildAdView`: the Prebid auction, drawn by Google Mobile Ads. Paused and resumed with the screen. */
@Composable
fun BannerAd(config: SellwildConfig, adSize: AdSize, zoneId: String, onStatus: (String) -> Unit) {
    val status by rememberUpdatedState(onStatus)
    val holder = remember { ViewHolder<SellwildAdView>() }
    PauseResumeEffect(onPause = { holder.view?.pause() }, onResume = { holder.view?.resume() })
    AndroidView(
        factory = { context ->
            SellwildAdView(context).apply {
                listener = object : SellwildAdView.Listener {
                    override fun onAdLoaded(adView: SellwildAdView) = status("Ad loaded")

                    override fun onAdImpression(adView: SellwildAdView, zoneId: String) =
                        status("Impression, zone $zoneId")

                    override fun onHouseAdImpression(adView: SellwildAdView, zoneId: String) =
                        status("House ad, zone $zoneId")

                    override fun onAdFailed(adView: SellwildAdView, message: String) = status("No ad: $message")
                }
                setup(config, adSize, zoneId)
                load()
                holder.view = this
            }
        },
        modifier = Modifier.fillMaxSize(),
        onRelease = { it.destroy() },
    )
}

/**
 * `SellwildNativeAdView`: Prebid native assets in the SDK's template. It stays hidden
 * until an ad fills, so a no-fill shows the empty slot, not an empty template.
 */
@Composable
fun NativeAd(config: SellwildConfig, zoneId: String, maxHeightDp: Int, onStatus: (String) -> Unit) {
    val status by rememberUpdatedState(onStatus)
    AndroidView(
        factory = { context ->
            SellwildNativeAdView(context, config, zoneId, maxHeightDp).apply {
                visibility = View.INVISIBLE
                // The fork may call back off the main thread: post the view changes.
                onLoaded = {
                    post { visibility = View.VISIBLE }
                    status("Ad loaded")
                }
                onImpression = { status("Impression") }
                onFailed = { message ->
                    post { visibility = View.INVISIBLE }
                    status("No ad: $message")
                }
                load()
            }
        },
        modifier = Modifier.fillMaxSize(),
        onRelease = { it.destroy() },
    )
}
