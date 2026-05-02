/**
 * Sellwild Android SDK — Runnable Sample App
 *
 * How to run:
 *   1. Create a new Android project in Android Studio (API 23+ / Kotlin).
 *   2. Add the SDK dependency to app/build.gradle.kts:
 *        implementation("com.sellwild:sdk:1.3.0")
 *        — OR for local Maven during development:
 *        implementation(files("../../android/build/outputs/aar/sdk-release.aar"))
 *      The SDK transitively pulls in Prebid Mobile 3.x and Google Mobile Ads
 *      24.x; you do not need to declare them yourself.
 *   3. Add INTERNET permission to AndroidManifest.xml:
 *        <uses-permission android:name="android.permission.INTERNET" />
 *   4. Add the Google Mobile Ads app ID to AndroidManifest.xml:
 *        <meta-data
 *          android:name="com.google.android.gms.ads.APPLICATION_ID"
 *          android:value="ca-app-pub-3940256099942544~3347511713" /> <!-- test -->
 *      Replace with your real GMA app ID before shipping.
 *   5. Copy the files below into your project.
 *   6. Replace 'YOUR_PARTNER_CODE' with your real partner code.
 *
 * The default route is `NativeBannerFragment` — a native banner ad backed by
 * Prebid Mobile + GMA, with no WebView in the ad path. The widget tab still
 * uses a WebView for the marketplace listings surface only; that is
 * intentional. Ads always render natively in 1.3.0+.
 *
 * Files covered:
 *   - MainActivity.kt          — entry point
 *   - NativeBannerFragment.kt  — default tab: native 320×50 banner
 *   - WidgetFragment.kt        — marketplace listings (WebView surface only)
 *   - NativeListingsFragment.kt — native RecyclerView + banner combo
 *   - ListingsViewModel.kt     — ViewModel using coroutines
 */

package com.example.sellwilddemo

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModelScope
import org.json.JSONObject
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.sellwild.sdk.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

// ─── Config ───────────────────────────────────────────────────────────────────
//
// `SellwildSDK.configure(partnerCode, slug)` fetches a JSON document from
//   https://widget.sellwild.com/app/{partnerCode}/{slug}.json
// and returns a fully-built SellwildConfig — listings URL, ad zones, refresh
// intervals, app identity, waterfall partners, compliance flags, all populated
// from the CMS. Two strings = working SDK. On any network/timeout/404 failure
// the SDK falls back to deterministic defaults so ads still render.
//
// In 1.3.0+ the auction itself runs natively via Prebid Mobile and renders
// into a Google `AdManagerAdView`; there is no WebView in the ad path.

private val STATIC_CONFIG = SellwildConfig(
    partnerCode = "YOUR_PARTNER_CODE",
    appBundleId = "com.mycompany.myapp",   // use BuildConfig.APPLICATION_ID in production
    appStoreUrl = "https://play.google.com/store/apps/details?id=com.mycompany.myapp",
    adRefreshMaxMobile = 5,
    adRefreshIntervalMs = 30_000L,
    debug = true,
)

private const val REMOTE_SLUG = "your-partner-slug"

private val DEMO_CONFIG = STATIC_CONFIG

private const val TAG = "SellwildDemo"

// ─── MainActivity ─────────────────────────────────────────────────────────────

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        FrameLayout(this).also { setContentView(it) }

        if (savedInstanceState == null) {
            // Lead with the native banner fragment — this is the
            // recommended integration path for 1.3.0+. Native auction,
            // native render, no WebView in the ad pipeline.
            supportFragmentManager.beginTransaction()
                .replace(android.R.id.content, NativeBannerFragment())
                .commit()
        }

        // To explore the other surfaces, swap the call above for one of:
        //   .replace(android.R.id.content, NativeListingsFragment())
        //   .replace(android.R.id.content, WidgetFragment())
    }
}

// ─── A. NativeBannerFragment — Default tab: native 320×50 banner ─────────────
//
// Minimal, copy-pasteable banner integration. `SellwildSDK.configure()` does
// the network fetch; `SellwildAdView` runs the Prebid auction and hands the
// winner to GMA. No WebView. No bridge. Just a view in your layout.

class NativeBannerFragment : Fragment() {

    private lateinit var bannerView: SellwildAdView

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val root = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER_HORIZONTAL
            setPadding(0, 32, 0, 0)
        }

        bannerView = SellwildAdView(requireContext())
        bannerView.listener = object : SellwildAdView.Listener {
            override fun onAdLoaded(adView: SellwildAdView) {
                Log.d(TAG, "Native banner loaded")
            }
            override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                Log.d(TAG, "Native banner impression, zoneId=$zoneId")
            }
            override fun onAdFailed(adView: SellwildAdView, message: String) {
                Log.w(TAG, "Native banner failed: $message")
            }
        }
        root.addView(bannerView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))

        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        viewLifecycleOwner.lifecycleScope.launch {
            // Two-string init. configure() fetches the CDN JSON and merges
            // it with defaults; the resulting config carries every key the
            // CMS shipped (typed first-class fields plus a `remoteJson`
            // passthrough for unmapped bidders like MEDIANET, AMX, SOVRN).
            val config = SellwildSDK.configure(
                partnerCode = STATIC_CONFIG.partnerCode,
                slug = REMOTE_SLUG,
            ) { c -> c.copy(appBundleId = STATIC_CONFIG.appBundleId, debug = true) }

            bannerView.setup(
                config = config,
                adSize = AdSize.BANNER_320x50,
                zoneId = config.bannerZid,
            )
            bannerView.load()
        }
    }

    override fun onResume() { super.onResume(); bannerView.resume() }
    override fun onPause()  { super.onPause();  bannerView.pause()  }
    override fun onDestroyView() { super.onDestroyView(); bannerView.destroy() }
}

// ─── B. WidgetFragment — Marketplace listings (WebView surface) ──────────────
//
// The widget surface intentionally renders the marketplace listing grid
// inside a WebView. This is *not* the ad pipeline — banners and other
// monetizing units render natively via [NativeBannerFragment] above.

class WidgetFragment : Fragment() {

    private lateinit var widgetView: SellwildWidgetView

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        widgetView = SellwildWidgetView(requireContext())
        widgetView.setup(DEMO_CONFIG)
        widgetView.listener = object : SellwildWidgetView.Listener {

            override fun onWidgetLoaded(widgetView: SellwildWidgetView) {
                Log.d(TAG, "Widget loaded")
            }

            override fun onListingTapped(listing: SellwildListing) {
                // listing.url is populated from the window.open() interception bridge
                listing.url?.let { url ->
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                }
            }

            override fun onAdImpression(widgetView: SellwildWidgetView, zoneId: String) {
                Log.d(TAG, "Ad impression, zoneId=$zoneId")
            }

            override fun onError(widgetView: SellwildWidgetView, message: String) {
                Log.e(TAG, "Widget error: $message")
            }
        }
        return widgetView
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Fetch remote config and re-setup the widget. This proves the
        // passthrough path end-to-end: configure() returns a SellwildConfig
        // whose `remoteJson` field carries every key from the CDN, including
        // unmapped bidders (MEDIANET, AMX, SOVRN, etc.).
        lifecycleScope.launch {
            val config = SellwildSDK.configure(
                partnerCode = STATIC_CONFIG.partnerCode,
                slug = REMOTE_SLUG,
            ) { c -> c.copy(appBundleId = STATIC_CONFIG.appBundleId, debug = true) }

            val keys = config.remoteJson?.let { raw ->
                runCatching { JSONObject(raw).keys().asSequence().toList().sorted() }
                    .getOrDefault(emptyList())
            } ?: emptyList()
            Log.d(TAG, "configure() resolved. remote passthrough keys: $keys")

            widgetView.setup(config)
            widgetView.load()
        }
    }

    override fun onResume() { super.onResume(); widgetView.resume() }
    override fun onPause()  { super.onPause();  widgetView.pause()  }
    override fun onDestroyView() { super.onDestroyView(); widgetView.destroy() }
}

// ─── C. NativeListingsFragment — Native banner + RecyclerView listings ──────

class NativeListingsFragment : Fragment() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ListingsAdapter
    private lateinit var bannerView: SellwildAdView
    private lateinit var progressBar: ProgressBar
    private lateinit var errorText: TextView
    private lateinit var vm: ListingsViewModel

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val root = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }

        // Top 320×50 banner
        bannerView = SellwildAdView(requireContext())
        bannerView.setup(DEMO_CONFIG, AdSize.BANNER_320x50,
            zoneId = DEMO_CONFIG.bannerZid)
        bannerView.listener = object : SellwildAdView.Listener {
            override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                Log.d(TAG, "Banner impression, zoneId=$zoneId")
            }
        }
        root.addView(bannerView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).also { it.gravity = android.view.Gravity.CENTER_HORIZONTAL })

        // Progress indicator
        progressBar = ProgressBar(requireContext())
        root.addView(progressBar)

        // Error text
        errorText = TextView(requireContext()).apply { visibility = View.GONE }
        root.addView(errorText)

        // Listings grid
        adapter = ListingsAdapter { listing ->
            listing.url?.let { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) }
        }
        recyclerView = RecyclerView(requireContext()).apply {
            layoutManager = GridLayoutManager(requireContext(), 2)
            this.adapter = this@NativeListingsFragment.adapter
            visibility = View.GONE
        }
        root.addView(recyclerView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))

        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        bannerView.load()

        vm = ViewModelProvider(this, ListingsViewModelFactory(requireContext()))
            .get(ListingsViewModel::class.java)

        viewLifecycleOwner.lifecycleScope.launch {
            vm.uiState.collect { state ->
                when (state) {
                    is ListingsUiState.Loading -> {
                        progressBar.visibility = View.VISIBLE
                        recyclerView.visibility = View.GONE
                        errorText.visibility = View.GONE
                    }
                    is ListingsUiState.Success -> {
                        progressBar.visibility = View.GONE
                        recyclerView.visibility = View.VISIBLE
                        errorText.visibility = View.GONE
                        adapter.submitList(state.listings)
                    }
                    is ListingsUiState.Error -> {
                        progressBar.visibility = View.GONE
                        recyclerView.visibility = View.GONE
                        errorText.visibility = View.VISIBLE
                        errorText.text = "Error: ${state.message}"
                    }
                }
            }
        }

        vm.load(DEMO_CONFIG)
    }

    override fun onResume()  { super.onResume();  bannerView.resume() }
    override fun onPause()   { super.onPause();   bannerView.pause()  }
    override fun onDestroyView() { super.onDestroyView(); bannerView.destroy() }
}

// ─── ListingsViewModel ────────────────────────────────────────────────────────

sealed class ListingsUiState {
    object Loading : ListingsUiState()
    data class Success(val listings: List<SellwildListing>) : ListingsUiState()
    data class Error(val message: String) : ListingsUiState()
}

class ListingsViewModel(private val context: android.content.Context) : ViewModel() {

    private val _uiState = MutableStateFlow<ListingsUiState>(ListingsUiState.Loading)
    val uiState: StateFlow<ListingsUiState> = _uiState

    private val apiClient = SellwildAPIClient(context)

    fun load(config: SellwildConfig) {
        viewModelScope.launch {
            _uiState.value = ListingsUiState.Loading
            apiClient.fetchListings(config)
                .onSuccess { response ->
                    _uiState.value = ListingsUiState.Success(response.listings)
                }
                .onFailure { error ->
                    _uiState.value = ListingsUiState.Error(error.message ?: "Unknown error")
                    Log.e(TAG, "Failed to load listings", error)
                }
        }
    }

    fun refresh(config: SellwildConfig) {
        apiClient.clearCache()
        load(config)
    }
}

class ListingsViewModelFactory(
    private val context: android.content.Context
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return ListingsViewModel(context) as T
    }
}

// ─── ListingsAdapter ──────────────────────────────────────────────────────────

class ListingsAdapter(
    private val onItemClick: (SellwildListing) -> Unit
) : RecyclerView.Adapter<ListingsAdapter.ViewHolder>() {

    private val items = mutableListOf<SellwildListing>()

    fun submitList(newItems: List<SellwildListing>) {
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val card = LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(8, 8, 8, 8)
            layoutParams = RecyclerView.LayoutParams(
                RecyclerView.LayoutParams.MATCH_PARENT,
                RecyclerView.LayoutParams.WRAP_CONTENT
            )
        }
        return ViewHolder(card)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(items[position], onItemClick)
    }

    override fun getItemCount() = items.size

    class ViewHolder(private val container: LinearLayout) : RecyclerView.ViewHolder(container) {
        private val titleView = TextView(container.context).apply {
            textSize = 13f
            maxLines = 2
            setTextColor(android.graphics.Color.parseColor("#222222"))
        }
        private val priceView = TextView(container.context).apply {
            textSize = 12f
            setTextColor(android.graphics.Color.parseColor("#0066cc"))
        }

        init {
            container.addView(titleView)
            container.addView(priceView)
        }

        fun bind(listing: SellwildListing, onClick: (SellwildListing) -> Unit) {
            titleView.text = listing.title
            priceView.text = listing.displayPrice?.let { "\$$it" } ?: ""
            container.setOnClickListener { onClick(listing) }
        }
    }
}

// ─── Extension to make Fragment use lifecycleScope ───────────────────────────
// (If not already available via lifecycle-runtime-ktx dependency)

private val Fragment.lifecycleScope get() =
    viewLifecycleOwner.lifecycleScope
