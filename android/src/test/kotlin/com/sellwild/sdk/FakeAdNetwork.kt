package com.sellwild.sdk

import android.content.Context
import android.os.Bundle
import android.view.View
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.admanager.AdManagerAdView
import com.sellwild.prebid.BannerAdUnit
import com.sellwild.prebid.NativeAdUnit
import com.sellwild.prebid.PrebidNativeAdEventListener
import com.sellwild.prebid.ResultCode
import com.sellwild.prebid.api.data.InitializationStatus
import com.sellwild.prebid.api.rendering.BannerView
import com.sellwild.sdk.factories.AppConfigFactory
import org.json.JSONObject
import org.junit.rules.ExternalResource
import java.util.concurrent.CopyOnWriteArrayList

/**
 * A [SellwildAdNetwork] that records every GMA and Prebid call that would need a device or
 * the network, and lets a test finish each one the way it wants (a status, a result code, a
 * native ad). Installed by [AdNetworkRule].
 */
internal class FakeAdNetwork : SellwildAdNetwork {
    var gmaError: Throwable? = null
    var prebidError: Throwable? = null

    val gmaInits = CopyOnWriteArrayList<Context>()
    val prebidHosts = CopyOnWriteArrayList<String>()
    var prebidStatus: ((InitializationStatus?) -> Unit)? = null

    val gamLoads = CopyOnWriteArrayList<AdManagerAdView>()
    val gamRequests = CopyOnWriteArrayList<AdManagerAdRequest>()
    val bannerAuctions = CopyOnWriteArrayList<BannerAuction>()
    val renderingLoads = CopyOnWriteArrayList<BannerView>()
    val nativeFetches = CopyOnWriteArrayList<NativeFetch>()

    /** What [nativeAd] returns per cache id; an id not here gives null. */
    val nativeAds = mutableMapOf<String, NativeAdContent>()

    class BannerAuction(val unit: BannerAdUnit, val request: AdManagerAdRequest, val finish: (ResultCode) -> Unit)

    class NativeFetch(val unit: NativeAdUnit, val adObject: Bundle, val finish: (ResultCode) -> Unit)

    override fun initializeGma(context: Context) {
        gmaError?.let { throw it }
        gmaInits += context
    }

    override fun initializePrebid(context: Context, hostUrl: String, onStatus: (InitializationStatus?) -> Unit) {
        prebidError?.let { throw it }
        prebidHosts += hostUrl
        prebidStatus = onStatus
    }

    override fun loadGam(view: AdManagerAdView, request: AdManagerAdRequest) {
        gamLoads += view
        gamRequests += request
    }

    override fun fetchBannerDemand(unit: BannerAdUnit, request: AdManagerAdRequest, onResult: (ResultCode) -> Unit) {
        bannerAuctions += BannerAuction(unit, request, onResult)
    }

    override fun loadRendering(view: BannerView) {
        renderingLoads += view
    }

    override fun fetchNativeDemand(unit: NativeAdUnit, adObject: Bundle, onResult: (ResultCode) -> Unit) {
        nativeFetches += NativeFetch(unit, adObject, onResult)
    }

    override fun nativeAd(cacheId: String): NativeAdContent? = nativeAds[cacheId]

    /** Finishes Prebid init the way the fork does, with [status]. */
    fun finishPrebidInit(status: InitializationStatus? = InitializationStatus.SUCCEEDED) {
        checkNotNull(prebidStatus) { "Prebid init was never started" }.invoke(status)
    }
}

/** A won native ad with fixed assets. [register] keeps what the view registered. */
internal class FakeNativeContent(
    override val title: String? = "Fixture native title",
    override val description: String? = "Fixture native body",
    override val sponsoredBy: String? = "Fixture Brand",
    override val callToAction: String? = "Shop now",
    override val iconUrl: String? = null,
    override val imageUrl: String? = null,
) : NativeAdContent {
    var container: View? = null
    var clickables: List<View> = emptyList()
    var events: PrebidNativeAdEventListener? = null

    override fun register(container: View, clickables: List<View>, listener: PrebidNativeAdEventListener) {
        this.container = container
        this.clickables = clickables
        events = listener
    }
}

/**
 * Installs a [FakeAdNetwork] and resets every process-wide seam the view shells use, before
 * and after each test: the Prebid bootstrap latch and readiness, the house and feed image
 * loaders, GrowthCode, the feed's API client factory and the stored geo. Use with
 * NetworkBlockRule and FailuresRule.
 */
class AdNetworkRule : ExternalResource() {
    internal lateinit var network: FakeAdNetwork
        private set

    override fun before() {
        reset()
        network = FakeAdNetwork()
        SellwildPrebidMobile.network = network
    }

    override fun after() = reset()

    private fun reset() {
        SellwildPrebidMobile.resetForTesting()
        SellwildHouseAd.resetForTests()
        FeedImages.resetForTests()
        SellwildGrowthCode.resetForTesting()
        SellwildFeedView.apiClient = ::SellwildAPIClient
        SellwildGeoStore.current = null
    }

    /** Bootstraps Prebid against the fake and finishes its init, so auctions run at once. */
    internal fun prebidReady(context: Context) {
        SellwildPrebidMobile.bootstrap(context, SellwildConfig(partnerCode = "fixture"))
        network.finishPrebidInit()
    }
}

/**
 * The SellwildConfig the SDK builds from [remote], a CDN app config: its typed fields mapped by
 * SellwildSDK.apply and the raw text kept as remoteJson, as configure() does.
 */
internal fun configFrom(remote: JSONObject = AppConfigFactory.checked()): SellwildConfig =
    SellwildSDK.apply(remote, SellwildConfig(partnerCode = "fixture")).copy(remoteJson = remote.toString())

/** [configFrom] a validated app config with [overrides]. */
internal fun configWith(vararg overrides: Pair<String, Any?>): SellwildConfig = configFrom(AppConfigFactory.checked(mapOf(*overrides)))

/**
 * What a Java test can read and do through an [AdNetworkRule]: the fake network's members are
 * internal, which Java sees only under mangled names.
 */
object AdNetworkAccess {
    /** The banner auctions started so far. */
    @JvmStatic
    fun bannerAuctions(rule: AdNetworkRule): Int = rule.network.bannerAuctions.size

    /** Finishes the latest banner auction with [result]. */
    @JvmStatic
    fun finishBannerAuction(rule: AdNetworkRule, result: com.sellwild.prebid.ResultCode) = rule.network.bannerAuctions.last().finish(result)

    /** The GAM loads so far. */
    @JvmStatic
    fun gamLoads(rule: AdNetworkRule): Int = rule.network.gamLoads.size
}
