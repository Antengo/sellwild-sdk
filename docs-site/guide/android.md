# Android Integration Guide

Sellwild SDK for Android -- native ad SDK powered by server-side header bidding through Prebid Server.

As of 1.3.0, banner ads render natively through `AdManagerAdView` (Google Mobile Ads SDK). Header bidding runs in-process via Prebid Mobile, with the auction itself served server-to-server by `prebid.sellwild.com`. There is no WebView in the ad-rendering path -- no client-side JavaScript bidding, no individual SSP SDKs, no waterfall latency.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Native banner path (1.3.0+)](#native-banner-path-1-3-0)
4. [Native Marketplace Feed (1.3.5+)](#native-marketplace-feed-1-3-5)
5. [AndroidManifest Configuration](#androidmanifest-configuration)
6. [Basic Integration](#basic-integration)
7. [Jetpack Compose](#jetpack-compose)
8. [Native Listing Cards](#native-listing-cards)
9. [Coroutines API](#coroutines-api)
10. [Remote Config](#remote-config)
11. [Prebid Server Configuration](#prebid-server-configuration)
12. [GDPR and Privacy](#gdpr-and-privacy)
13. [Lifecycle Management](#lifecycle-management)
14. [Ad Refresh](#ad-refresh)
15. [ProGuard and R8](#proguard-and-r8)
16. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Minimum Version |
|---|---|
| Android Studio | Hedgehog (2023.1.1) or later |
| Kotlin | 1.9.0+ |
| `minSdk` | 23 (Android 6.0 Marshmallow) — raised from 21 in 1.3.0 for Prebid Mobile 3.x |
| `compileSdk` | 35 |
| `targetSdk` | 35 |
| Gradle | 8.2+ |
| AGP (Android Gradle Plugin) | 8.1+ |

The SDK is written in pure Kotlin with no native (NDK) dependencies. It requires `kotlinx-coroutines-android` for the async listings API. As of 1.3.0 it also depends on Prebid Mobile `3.3.0` and Google Mobile Ads `22.6.0` for the native banner rendering path; both are pulled in transitively.

---

## Installation

### Gradle (recommended)

**Step 1 -- Add the Sellwild Maven repository.**

In your project-level `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.sellwild.com/releases")
            content {
                includeGroupByRegex("com\\.sellwild.*")
            }
        }
    }
}
```

**Step 2 -- Add the SDK dependency.**

In your app-level `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.sellwild:sdk:1.4.0")

    // Required -- coroutines for async listings API
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

Sync your project and rebuild.

### Maven Local (offline or CI builds)

If you received the SDK as an `.aar` file, publish it to your local Maven repository:

```bash
# From the directory containing sellwild-sdk-1.1.0.aar
mvn install:install-file \
    -Dfile=sellwild-sdk-1.1.0.aar \
    -DgroupId=com.sellwild \
    -DartifactId=sellwild-sdk \
    -Dversion=1.1.0 \
    -Dpackaging=aar
```

Then add `mavenLocal()` to your repositories block in `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        mavenLocal()
    }
}
```

---

## Native banner path (1.3.0+)

As of 1.3.0, `SellwildAdView` no longer renders banner creatives in a `WebView`. It hosts a native `AdManagerAdView` (Google Mobile Ads SDK) and runs a Prebid Mobile auction in-process before loading the GAM view.

- **First-use bootstrap.** The first time a `SellwildAdView` is created, `SellwildPrebidMobile.bootstrap()` initializes Prebid Mobile (host, account ID, timeouts) using values from `SellwildConfig.prebidServer`. Subsequent ad views reuse the initialized stack.
- **Auction flow.** `SellwildAdView.load()` builds an OpenRTB request with Prebid Mobile, sends it to `prebid.sellwild.com`, applies the winning bid's keywords as targeting on an `AdManagerAdRequest`, then calls `AdManagerAdView.loadAd(...)`. The GAM SDK selects between the Prebid line item and any direct-sold demand and renders the creative natively.
- **Required manifest entry.** GMA will not initialize without the `com.google.android.gms.ads.APPLICATION_ID` `meta-data` entry. See [AndroidManifest Configuration](#androidmanifest-configuration) below.
- **Marketplace listings.** `SellwildWidgetView` is a separate surface for the marketplace listings widget and is unrelated to the ad path. If your integration only requires banner ads, you do not need to use it.

If you want to bypass the native ad path entirely and consume bids yourself, see [Prebid Server Configuration](#prebid-server-configuration).

---

## Native Marketplace Feed (1.3.5+)

`SellwildFeedView` renders a full-screen native marketplace feed with listings and interleaved Prebid + GAM ads. It uses `RecyclerView` internally — no WebView in the rendering path.

The feed layout is driven by your CDN config's `COL1` schedule (e.g., `"LLGLLGLLG"` = listing, listing, GAM ad, repeat). Listings are fetched from your configured listings endpoint; ads run the same Prebid → GAM auction as `SellwildAdView`.

### Jetpack Compose

```kotlin
import androidx.compose.runtime.*
import com.sellwild.sdk.*

@Composable
fun MarketplaceScreen(config: SellwildConfig) {
    SellwildFeed(
        config = config,
        onLoad = { Log.d("Sellwild", "Feed loaded") },
        onListingTap = { listing ->
            Log.d("Sellwild", "Tapped: ${listing.title}")
            false // false = SDK opens in Custom Tabs
        },
        onAdImpression = { zoneId -> Log.d("Sellwild", "Ad impression: $zoneId") },
        onAdClicked = { zoneId -> Log.d("Sellwild", "Ad clicked: $zoneId") },
        onError = { error -> Log.e("Sellwild", "Feed error: $error") }
    )
}
```

### XML Views

```kotlin
import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.sellwild.sdk.*
import kotlinx.coroutines.launch

class FeedActivity : AppCompatActivity() {
    private lateinit var feedView: SellwildFeedView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        feedView = SellwildFeedView(this)
        setContentView(feedView)

        feedView.listener = object : SellwildFeedView.Listener {
            override fun onLoad() {
                Log.d("Sellwild", "Feed loaded")
            }

            override fun onListingTap(listing: SellwildListing): Boolean {
                Log.d("Sellwild", "Tapped: ${listing.title} - ${listing.formattedPrice}")
                return false // false = SDK opens in Custom Tabs
            }

            override fun onAdImpression(zoneId: String) {
                Log.d("Sellwild", "Ad impression: $zoneId")
            }

            override fun onAdClicked(zoneId: String) {
                Log.d("Sellwild", "Ad clicked: $zoneId")
            }

            override fun onError(message: String) {
                Log.e("Sellwild", "Feed error: $message")
            }
        }

        lifecycleScope.launch {
            val config = SellwildSDK.configure(
                partnerCode = "weatherbug",
                slug = "weatherbug-weatherbug"
            )
            feedView.setup(config)
            feedView.load()
        }
    }

    override fun onDestroy() {
        feedView.destroy()
        super.onDestroy()
    }
}
```

### Listing Tap Handling

The `onListingTap` listener method returns a `Boolean`:

- **Return `false`** (recommended): The SDK opens the listing URL in Chrome Custom Tabs. This matches the WebView widget behavior.
- **Return `true`**: You handle navigation yourself. The SDK does nothing.

### Embedding in a Scroll View (1.4.0+)

To place the feed inside a parent scroll view (a single-scroll page — e.g. alongside a Taboola feed), disable the feed's own scrolling and let the host size its container from the content-height callback:

```kotlin
feedView.scrollEnabled = false

feedView.listener = object : SellwildFeedView.Listener {
    override fun onContentHeightChanged(feedView: SellwildFeedView, heightDp: Int) {
        // Size the feed's container (heightDp is in dp).
        feedView.updateLayoutParams { height = dpToPx(heightDp) }
    }
    // ... other Listener methods
}
```

With `scrollEnabled = false` the recycler switches to `WRAP_CONTENT` so the parent can scroll it fully. You can also read the current height imperatively via `feedView.contentHeightDp`.

> **Caveats.** Disabling scroll turns **off** pull-to-refresh (it needs the scroll gesture) — the host must drive refresh (e.g. call `feedView.refresh()`). The feed also renders **all** rows (no `RecyclerView` virtualization), so keep embedded feeds reasonably sized. `scrollEnabled` defaults to `true`; full-screen integrations are unaffected.

### Feed Configuration

The feed respects these CDN config keys:

| Key | Description |
|-----|-------------|
| `COL1` | Row schedule string (e.g., `"LLGLLGLLG"` — L=listing, G=GAM ad) |
| `LISTINGS` | URL to fetch listing JSON |
| `TITLE` | Header title (default: "Marketplace") |
| `BG_COLOR` | Background color (hex, e.g., `"#F5F5F5"`) |
| `MOBILE_ZIDS` | Array of zone IDs for interleaved ads |

---

## AndroidManifest Configuration

### Google Mobile Ads Application ID (required, 1.3.0+)

The Google Mobile Ads SDK refuses to initialize without an `APPLICATION_ID` meta-data entry. Add it inside `<application>`:

```xml
<application ... >
    <meta-data
        android:name="com.google.android.gms.ads.APPLICATION_ID"
        android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY" />
</application>
```

Use **your own** AdMob / Ad Manager app ID — the one you already use for your Android app. Google Mobile Ads is initialized once per process, so the SDK reuses your host app's `APPLICATION_ID`; Sellwild does not issue or override it. Ad unit / zone IDs come from your Sellwild CDN config (`widget.sellwild.com/app/{partnerCode}/{slug}.json`) and map to GAM ad units on our side.

- **Self-managed inventory (most common):** Register your app at [admanager.google.com](https://admanager.google.com) or [apps.admob.com](https://apps.admob.com); Google issues a `ca-app-pub-...~...` ID.
- **Managed inventory:** If Sellwild operates your GAM network, your account manager will provision the app ID for you.
- **Development only:** Google's sample ID `ca-app-pub-3940256099942544~1458002511` works for local builds but **must not** ship to Google Play.

Apps built without this meta-data will crash on first ad load.

### Required Permissions

Add the following permissions to your `AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Required: network access for ad auctions and listing fetches -->
    <uses-permission android:name="android.permission.INTERNET" />

    <!-- Recommended: enables the SDK to skip requests when offline -->
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <!-- ... -->
</manifest>
```

### Network Security Configuration

The SDK communicates with `prebid.sellwild.com` over HTTPS. However, certain ad creatives served by Google Ad Manager require cleartext HTTP access to specific domains during rendering. You have two options.

**Option A -- Allow cleartext globally (simple, not recommended for production):**

```xml
<application
    android:usesCleartextTraffic="true"
    ... >
```

**Option B -- Network Security Config with domain exceptions (recommended):**

Create `res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Default: block cleartext -->
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>

    <!-- Allow cleartext only for ad-serving domains -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">sellwild.com</domain>
        <domain includeSubdomains="true">doubleclick.net</domain>
        <domain includeSubdomains="true">googlesyndication.com</domain>
    </domain-config>
</network-security-config>
```

Reference it in your `AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ... >
```

---

## Basic Integration

The following example shows a complete Activity with two ad placements: a 300x250 MREC and a 320x50 banner. Both run server-side header bidding through Prebid Server at `prebid.sellwild.com`.

::: tip Recommended: use `configure()`
For most integrations, call `SellwildSDK.configure(partnerCode, slug)` from a
coroutine instead of building `SellwildConfig` by hand. It fetches your partner
config from `https://widget.sellwild.com/app/{partnerCode}/{slug}.json` and
populates every field below automatically. The static example below is shown
only to document each field.
:::

```kotlin
package com.example.myapp

import android.os.Bundle
import android.util.Log
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import com.sellwild.sdk.*

class AdActivity : AppCompatActivity() {

    private lateinit var mrecAdView: SellwildAdView
    private lateinit var bannerAdView: SellwildAdView

    // Static example. In production prefer:
    //   lifecycleScope.launch {
    //       val config = SellwildSDK.configure(
    //           partnerCode = "weatherbug",
    //           slug = "weatherbug-weatherbug",
    //       )
    //   }
    private val config = SellwildConfig(
        partnerCode = "weatherbug",
        appBundleId = "com.aws.android",
        appStoreUrl = "https://play.google.com/store/apps/details?id=com.aws.android",
        prebidServer = PrebidServerConfig(
            accountId = "sellwild",
            endpoint = "https://prebid.sellwild.com/openrtb2/auction",
            bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
            timeout = 1500
        )
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
        }

        // --- 300x250 MREC ---
        mrecAdView = SellwildAdView(this)
        mrecAdView.setup(config, AdSize.MREC_300x250)
        mrecAdView.listener = object : SellwildAdView.Listener {
            override fun onAdLoaded(adView: SellwildAdView) {
                Log.d("SellwildAd", "MREC loaded")
            }

            override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                Log.d("SellwildAd", "MREC impression recorded (zone=$zoneId)")
            }

            override fun onAdClicked(adView: SellwildAdView) {
                Log.d("SellwildAd", "MREC clicked")
            }

            override fun onAdFailed(adView: SellwildAdView, message: String) {
                Log.e("SellwildAd", "MREC failed: $message")
            }
        }
        rootLayout.addView(mrecAdView)
        mrecAdView.load()

        // --- 320x50 Banner ---
        bannerAdView = SellwildAdView(this)
        bannerAdView.setup(config, AdSize.BANNER_320x50)
        bannerAdView.listener = object : SellwildAdView.Listener {
            override fun onAdLoaded(adView: SellwildAdView) {
                Log.d("SellwildAd", "Banner loaded")
            }

            override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                Log.d("SellwildAd", "Banner impression recorded (zone=$zoneId)")
            }

            override fun onAdFailed(adView: SellwildAdView, message: String) {
                Log.e("SellwildAd", "Banner failed: $message")
            }
        }
        rootLayout.addView(bannerAdView)
        bannerAdView.load()

        setContentView(rootLayout)
    }

    override fun onResume() {
        super.onResume()
        mrecAdView.resume()
        bannerAdView.resume()
    }

    override fun onPause() {
        super.onPause()
        mrecAdView.pause()
        bannerAdView.pause()
    }

    override fun onDestroy() {
        mrecAdView.destroy()
        bannerAdView.destroy()
        super.onDestroy()
    }
}
```

### Listener Callbacks

| Callback | When It Fires |
|---|---|
| `onAdLoaded(adView)` | The auction has resolved and the creative has been rendered into the underlying `AdManagerAdView`. |
| `onAdImpression(adView, zoneId)` | A viewable impression has been recorded. Use this for internal analytics. |
| `onAdClicked(adView)` | The user tapped on the ad creative. |
| `onAdFailed(adView, message)` | The auction returned no fill, or an error occurred during rendering. |

All callbacks are dispatched on the main thread.

---

## Jetpack Compose

Wrap `SellwildAdView` in an `AndroidView` composable. The `DisposableEffect` ensures correct lifecycle cleanup.

```kotlin
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.sellwild.sdk.*

@Composable
fun SellwildBanner(
    config: SellwildConfig,
    adSize: AdSize,
    modifier: Modifier = Modifier,
    zoneId: String? = null,
    onAdLoaded: (() -> Unit)? = null,
    onAdImpression: ((String) -> Unit)? = null,
    onAdFailed: ((String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val adView = remember {
        SellwildAdView(context).apply {
            setup(config, adSize, zoneId)
            listener = object : SellwildAdView.Listener {
                override fun onAdLoaded(adView: SellwildAdView) {
                    onAdLoaded?.invoke()
                }

                override fun onAdImpression(adView: SellwildAdView, zoneId: String) {
                    onAdImpression?.invoke(zoneId)
                }

                override fun onAdFailed(adView: SellwildAdView, message: String) {
                    onAdFailed?.invoke(message)
                }
            }
        }
    }

    DisposableEffect(Unit) {
        adView.load()
        onDispose {
            adView.destroy()
        }
    }

    AndroidView(
        factory = { adView },
        modifier = modifier,
    )
}
```

**Usage in a Compose screen:**

```kotlin
@Composable
fun HomeScreen() {
    val config = remember {
        SellwildConfig(
            partnerCode = "weatherbug",
            appBundleId = "com.aws.android",
            prebidServer = PrebidServerConfig(
                accountId = "sellwild",
                endpoint = "https://prebid.sellwild.com/openrtb2/auction",
                bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx")
            )
        )
    }

    Column {
        Text("Weather Forecast", style = MaterialTheme.typography.headlineMedium)

        // 300x250 MREC between content sections
        SellwildBanner(
            config = config,
            adSize = AdSize.MREC_300x250,
            onAdLoaded = { Log.d("Ad", "MREC ready") }
        )

        // Content continues...

        // 320x50 banner at the bottom
        SellwildBanner(
            config = config,
            adSize = AdSize.BANNER_320x50,
        )
    }
}
```

---

## Native Listing Cards

Use `SellwildAPIClient` to fetch marketplace listings and display them in a `RecyclerView`. Listing cards render with native Android views.

### Data Model

```kotlin
// These classes are provided by the SDK:

data class SellwildListing(
    val id: String,
    val status: String,
    val title: String,
    val price: String?,
    val currency: String?,
    val photos: List<SellwildPhoto>,
    val url: String?,
    // ... additional fields
) {
    val displayPrice: String?   // Formatted price string
    val primaryPhotoUrl: String? // First photo URL, or null
}
```

### RecyclerView Adapter

```kotlin
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.sellwild.sdk.SellwildListing

class ListingAdapter(
    private val onListingClick: (SellwildListing) -> Unit,
) : ListAdapter<SellwildListing, ListingAdapter.ViewHolder>(ListingDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_listing_card, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val listing = getItem(position)
        holder.bind(listing)
        holder.itemView.setOnClickListener { onListingClick(listing) }
    }

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val titleView: TextView = view.findViewById(R.id.listing_title)
        private val priceView: TextView = view.findViewById(R.id.listing_price)
        private val imageView: ImageView = view.findViewById(R.id.listing_image)

        fun bind(listing: SellwildListing) {
            titleView.text = listing.title
            priceView.text = listing.displayPrice?.let { "$$it" } ?: ""
            // Load image with your preferred library (Coil, Glide, Picasso)
            listing.primaryPhotoUrl?.let { url ->
                // Example with Coil:
                // imageView.load(url) { crossfade(true) }
            }
        }
    }
}

private class ListingDiffCallback : DiffUtil.ItemCallback<SellwildListing>() {
    override fun areItemsTheSame(old: SellwildListing, new: SellwildListing) = old.id == new.id
    override fun areContentsTheSame(old: SellwildListing, new: SellwildListing) = old == new
}
```

### Layout (`res/layout/item_listing_card.xml`)

```xml
<?xml version="1.0" encoding="utf-8"?>
<com.google.android.material.card.MaterialCardView
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="180dp"
    android:layout_height="wrap_content"
    android:layout_margin="8dp"
    app:cardCornerRadius="12dp"
    app:cardElevation="2dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical">

        <ImageView
            android:id="@+id/listing_image"
            android:layout_width="match_parent"
            android:layout_height="140dp"
            android:scaleType="centerCrop"
            android:contentDescription="@string/listing_image_desc" />

        <TextView
            android:id="@+id/listing_title"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:padding="8dp"
            android:maxLines="2"
            android:ellipsize="end"
            android:textSize="14sp" />

        <TextView
            android:id="@+id/listing_price"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:paddingStart="8dp"
            android:paddingEnd="8dp"
            android:paddingBottom="8dp"
            android:textSize="16sp"
            android:textStyle="bold"
            android:textColor="@color/black" />
    </LinearLayout>

</com.google.android.material.card.MaterialCardView>
```

---

## Coroutines API

`SellwildAPIClient.fetchListings()` is a `suspend` function. Call it from a `ViewModel` using `viewModelScope`.

```kotlin
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sellwild.sdk.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class ListingsViewModel(
    private val apiClient: SellwildAPIClient,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ListingsUiState>(ListingsUiState.Loading)
    val uiState: StateFlow<ListingsUiState> = _uiState

    private val config = SellwildConfig(
        partnerCode = "weatherbug",
        appBundleId = "com.aws.android",
        prebidServer = PrebidServerConfig(
            accountId = "sellwild",
            endpoint = "https://prebid.sellwild.com/openrtb2/auction",
            bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx")
        )
    )

    init {
        loadListings()
    }

    fun loadListings() {
        viewModelScope.launch {
            _uiState.value = ListingsUiState.Loading

            apiClient.fetchListings(config)
                .onSuccess { response ->
                    _uiState.value = ListingsUiState.Success(response.listings)
                }
                .onFailure { error ->
                    _uiState.value = ListingsUiState.Error(
                        error.message ?: "Failed to load listings"
                    )
                }
        }
    }

    fun refresh() {
        apiClient.clearCache()
        loadListings()
    }
}

sealed interface ListingsUiState {
    data object Loading : ListingsUiState
    data class Success(val listings: List<SellwildListing>) : ListingsUiState
    data class Error(val message: String) : ListingsUiState
}
```

**Key points:**

- `fetchListings()` switches to `Dispatchers.IO` internally. You do not need to wrap it in `withContext`.
- Results are cached by URL. Call `apiClient.clearCache()` before re-fetching if you need fresh data.
- The function returns `Result<SellwildListingsResponse>`, so use `.onSuccess` / `.onFailure` for structured error handling.

---

## Remote Config (the first-class path)

`SellwildSDK.configure(partnerCode, slug)` is the recommended way to integrate the SDK. It fetches a JSON document from the Sellwild CDN at app launch and returns a fully-built `SellwildConfig` — ad zones, refresh intervals, app identity, waterfall partners, compliance flags, and more — so you can change everything without an app update.

```kotlin
import com.sellwild.sdk.SellwildSDK

lifecycleScope.launch {
    val config = SellwildSDK.configure(
        partnerCode = "weatherbug",
        slug = "weatherbug-weatherbug",
    ) { c ->
        // Optional: override CDN values with app-controlled ones.
        c.copy(appBundleId = packageName)
    }
    // Hand `config` to your SellwildAdView / SellwildWidgetView.
}
```

The CDN URL is `https://widget.sellwild.com/app/{partnerCode}/{slug}.json`. Your Sellwild contact provisions the `slug` in the CMS.

**Failure handling.** On any network error, timeout, or 404 the call falls back to a `SellwildConfig(partnerCode = ...)` with deterministic defaults, so ads still render even with the CDN offline. Remote config is **additive, never blocking**.

> The CDN's `AD_REFRESH_INTERVAL` is in **seconds**, while Android's `adRefreshIntervalMs` is in **milliseconds**. `SellwildSDK.configure()` handles the conversion.

See [Configuration → Remote Config](./configuration#remote-config) for the full CDN field reference.

---

## Prebid Server Configuration

All header bidding runs server-side through the Sellwild managed Prebid Server instance. Configure it via `PrebidServerConfig`.

```kotlin
val prebidServer = PrebidServerConfig(
    accountId = "sellwild",
    endpoint = "https://prebid.sellwild.com/openrtb2/auction",
    bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx"),
    timeout = 1500,
    syncEndpoint = "https://prebid.sellwild.com/cookie_sync"  // optional
)
```

### Configuration Reference

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `accountId` | `String` | Yes | -- | Your Prebid Server account ID. |
| `endpoint` | `String` | Yes | -- | Full URL to the PBS `/openrtb2/auction` endpoint. |
| `bidders` | `List<String>` | Yes | -- | SSP bidder codes to include in the server-side auction. Must match adapters configured on your Prebid Server instance. |
| `timeout` | `Int` | No | `1500` | Server-side auction timeout in milliseconds. |
| `syncEndpoint` | `String?` | No | `null` | PBS `/cookie_sync` endpoint URL. Derived from `endpoint` if omitted. |

### How It Works

1. `SellwildAdView.load()` builds an OpenRTB 2.6 request with Prebid Mobile using the parameters from `PrebidServerConfig` plus any passthrough fields from `SellwildConfig.remote`.
2. Prebid Mobile posts a single request to `prebid.sellwild.com/openrtb2/auction`. Prebid Server fans out to all configured bidders in parallel, server-side.
3. The winning bid's keywords are attached to an `AdManagerAdRequest` as targeting.
4. `AdManagerAdView.loadAd(...)` is called. Google Ad Manager selects between the Prebid line item and any direct-sold demand and renders the creative through the native GMA view.

This architecture provides sub-200ms auction latency, eliminates client-side SDK bloat, and enables server-side bidder configuration changes without app updates.

### Available Bidders

The following SSPs are enabled on `prebid.sellwild.com`:

AppNexus/Xandr, PubMatic, Magnite/Rubicon, Index Exchange, OpenX, TripleLift, Sharethrough, InMobi, Smaato, Yieldmo, Unruly, Media.net, Sovrn, and 380+ additional adapters.

Contact sdk@sellwild.com to enable additional bidders for your account.

---

### External User IDs (eids)

Pass authenticated universal IDs (UID2, ID5, LiveRamp RampID, …) as `user.ext.eids` by calling `SellwildPrebidMobile.setExternalUserIds(...)` once per session with `SellwildEid` / `SellwildEidUid`. You supply the IDs — the SDK can't mint them.

See **[External User IDs (eids)](./prebid-server.md#external-user-ids-eids)** for full wiring, `atype` values, and server-side eid permissions.

### Outstream Video

Outstream (in-banner) video is supported and **toggled from remote config** (`VIDEO_ENABLED` / `VIDEO_ENABLED_BY_ZONE`) — no app release to turn it on/off. On `both` (GAM) zones it needs a GAM outstream line item; on `prebidOnly` zones Prebid renders it directly.

See **[Outstream Video](./prebid-server.md#outstream-video)** for enabling, rendering paths, and parameters.

### Native Ad Format

The Prebid native ad format is supported and **toggled from remote config** (`NATIVE_ENABLED` / `NATIVE_ENABLED_BY_ZONE`) — no app release. Native renders only on `prebidOnly` zones (the SDK lays out the assets itself into a default template and registers impression/click tracking); on `both`/`gamOnly` the zone falls through to a banner. A per-zone render-height cap (`NATIVE_MAX_HEIGHT` / `NATIVE_MAX_HEIGHT_BY_ZONE`) bounds the view.

See **[Native Ad Format](./prebid-server.md#native-ad-format)** for assets, the height cap, and rendering rules.

### Multi-Size Banners

A placement can request additional banner sizes (`BANNER_SIZES` / `BANNER_SIZES_BY_ZONE`) so demand falls back to a smaller creative when the primary doesn't fill — one unified auction, applied on all three stacks. Remember the winning size can change the rendered height; give the slot a container that tolerates the size set.

See **[Multi-Size Banners](./prebid-server.md#multi-size-banners)** for the config format and per-stack behavior.

## GDPR and Privacy

The SDK supports IAB TCF v2 consent management. For users in GDPR regions, you must pass consent information obtained from your Consent Management Platform (CMP).

### Configuration

```kotlin
val config = SellwildConfig(
    partnerCode = "weatherbug",
    appBundleId = "com.aws.android",

    // Privacy
    gppEnabled = true,
    tcfVersion = 2,

    prebidServer = PrebidServerConfig(
        accountId = "sellwild",
        endpoint = "https://prebid.sellwild.com/openrtb2/auction",
        bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx")
    )
)
```

### Bridging Consent from a Native CMP

If your app uses a native CMP (OneTrust, Didomi, Usercentrics, etc.), the consent string is stored in `SharedPreferences` per the IAB TCF v2 specification. You must read it and provide it to the SDK before loading ads.

```kotlin
import android.preference.PreferenceManager

// Read IAB TCF v2 consent values from SharedPreferences
val prefs = PreferenceManager.getDefaultSharedPreferences(context)
val gdprApplies = prefs.getInt("IABTCF_gdprApplies", 0) == 1
val tcString = prefs.getString("IABTCF_TCString", "") ?: ""
```

Pass these values when constructing your config. Prebid Server enforces consent -- bidders that lack consent for required purposes are automatically excluded from the auction.

### Privacy by Region

| Region | Behavior |
|---|---|
| **US traffic** | No consent string required. CCPA is enforced by Prebid Server by default. |
| **EU/EEA traffic** | Set `gdprApplies = true` and provide the TC string from your CMP. Bidders without valid consent are excluded. |
| **All regions** | The SDK does not collect or store personal data. Device advertising IDs (GAID) are not read by the SDK. |

---

## Lifecycle Management

`SellwildAdView` wraps an `AdManagerAdView` and schedules ad-refresh timers. Forwarding the host Activity or Fragment lifecycle is required to release these resources, stop pending refreshes, and avoid leaking the host context.

### Required Lifecycle Calls

```kotlin
class AdActivity : AppCompatActivity() {

    private lateinit var adView: SellwildAdView

    override fun onResume() {
        super.onResume()
        adView.resume()   // Resumes the underlying AdManagerAdView.
    }

    override fun onPause() {
        super.onPause()
        adView.pause()    // Pauses the underlying AdManagerAdView and cancels pending refresh timers.
    }

    override fun onDestroy() {
        adView.destroy()  // Releases the AdManagerAdView and detaches all listeners.
        super.onDestroy()
    }
}
```

| Method | What It Does |
|---|---|
| `resume()` | Calls `AdManagerAdView.resume()`. Refresh scheduling resumes on the next impression callback. |
| `pause()` | Calls `AdManagerAdView.pause()` and cancels any pending refresh timer. Safe to call repeatedly. |
| `destroy()` | Calls `pause()` then `AdManagerAdView.destroy()`. The `SellwildAdView` instance must not be used after this call. |

---

## Ad Refresh

The SDK supports automatic ad refresh to maximize revenue from long-lived screens. After an impression is recorded, the SDK waits for the configured interval and then re-auctions the ad slot.

### Configuration

```kotlin
val config = SellwildConfig(
    partnerCode = "weatherbug",
    appBundleId = "com.aws.android",

    // Refresh settings
    adRefreshMaxMobile = 10,        // Maximum number of refreshes per session (0 = unlimited)
    adRefreshIntervalMs = 30_000L,  // Interval between refreshes in milliseconds (min: 30000)

    prebidServer = PrebidServerConfig(
        accountId = "sellwild",
        endpoint = "https://prebid.sellwild.com/openrtb2/auction",
        bidders = listOf("appnexus", "pubmatic", "ix", "rubicon", "openx")
    )
)
```

### Refresh Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `adRefreshMaxMobile` | `Int` | `0` | Maximum refresh count for mobile. `0` disables refresh. Falls back to `adRefreshMax` if set to `0` and `adRefreshMax` is nonzero. |
| `adRefreshMax` | `Int` | `0` | Maximum refresh count (all platforms). Overridden by `adRefreshMaxMobile` on Android. |
| `adRefreshIntervalMs` | `Long` | `30000` | Milliseconds between refresh cycles. IAB guidelines recommend a minimum of 30 seconds. |

### Behavior

- Refresh scheduling starts after the first `onAdImpression` callback.
- Calling `pause()` cancels pending refresh timers. Calling `resume()` does **not** restart them -- the next refresh is triggered by the next impression.
- Refresh stops when `adRefreshMaxMobile` (or `adRefreshMax`) is reached.

---

## ProGuard and R8

If your app uses code shrinking (R8 or ProGuard), add the following keep rules to your `proguard-rules.pro` file:

```txt
# Sellwild SDK -- preserve listener interfaces used for ad callbacks.
-keep interface com.sellwild.sdk.SellwildAdView$Listener { *; }

# Preserve data classes used for JSON deserialization of remote config.
-keepclassmembers class com.sellwild.sdk.SellwildConfig { *; }
-keepclassmembers class com.sellwild.sdk.PrebidServerConfig { *; }
-keepclassmembers class com.sellwild.sdk.SellwildListing { *; }
-keepclassmembers class com.sellwild.sdk.SellwildPhoto { *; }
-keepclassmembers class com.sellwild.sdk.SellwildUser { *; }

# Preserve AdSize enum values referenced from generated code.
-keepclassmembers enum com.sellwild.sdk.AdSize {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
```

Prebid Mobile and Google Mobile Ads ship their own consumer ProGuard rules, which are applied automatically when you depend on the Sellwild SDK.

---

## Troubleshooting

### No Fill (Ad Not Loading)

**Symptom:** `onAdFailed` fires with a "no fill" or empty response message. The ad slot remains blank.

**Possible causes:**

| Cause | Resolution |
|---|---|
| No bidders configured | Verify `prebidServer.bidders` contains valid bidder codes. |
| Invalid account ID | Confirm `prebidServer.accountId` matches your Sellwild account. |
| Endpoint unreachable | Test `https://prebid.sellwild.com/openrtb2/auction` from the device. |
| Low traffic volume | Some SSPs suppress bids for new placements until they accumulate impression data. |
| Geographic restrictions | Certain bidders only operate in specific regions. |

**Debug mode:** Set `debug = true` in your `SellwildConfig` to enable verbose Prebid Mobile and GMA logging in `logcat`. Filter by tag `Sellwild` for SDK lifecycle events, `PrebidMobile` for the auction request and response, and `Ads` for GMA load and render events.

---

### GDPR Consent Blocking Ads

**Symptom:** Ads load in the US but not in EU/EEA regions. No error callback fires.

**Cause:** Prebid Server enforces GDPR consent. If no TC string is provided for EU traffic, all bidders are excluded from the auction.

**Fix:** Ensure your CMP is initialized before loading ads. Read the consent string from `SharedPreferences` (key: `IABTCF_TCString`) and verify it is non-empty for EU users.

---

### App Crashes on Launch (Missing GMA Application ID)

**Symptom:** The app crashes immediately on startup with a `java.lang.IllegalStateException` referencing `com.google.android.gms.ads.APPLICATION_ID`.

**Cause:** The Google Mobile Ads SDK refuses to initialize without an `APPLICATION_ID` `meta-data` entry in `AndroidManifest.xml`.

**Fix:** Add the entry described in [AndroidManifest Configuration](#androidmanifest-configuration) and rebuild.

---

### Ad Callbacks Not Firing (R8/ProGuard)

**Symptom:** Ads render but `onAdLoaded`, `onAdImpression`, or `onAdFailed` never fire.

**Cause:** R8 has stripped the `SellwildAdView.Listener` interface or one of the data classes used to deserialize the remote config response.

**Fix:** Add the ProGuard keep rules listed in [ProGuard and R8](#proguard-and-r8). Rebuild and verify.

---

## Support

- **Integration support:** sdk@sellwild.com
- **Documentation:** [Sellwild SDK Docs](https://github.com/sellwild/sellwild-sdk/tree/main/docs)
- **Prebid Server status:** [prebid.sellwild.com](https://prebid.sellwild.com)

---

Copyright 2026 Sellwild, Inc. All rights reserved.
