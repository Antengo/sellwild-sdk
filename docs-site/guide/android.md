# Android Integration Guide

Sellwild SDK for Android -- native ad SDK powered by server-side header bidding through Prebid Server.

All auctions run server-to-server via `prebid.sellwild.com`. The SDK renders ads in a lightweight managed WebView. No client-side JavaScript bidding, no individual SSP SDKs, no waterfall latency.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [AndroidManifest Configuration](#androidmanifest-configuration)
4. [Basic Integration](#basic-integration)
5. [Jetpack Compose](#jetpack-compose)
6. [Native Listing Cards](#native-listing-cards)
7. [Coroutines API](#coroutines-api)
8. [Prebid Server Configuration](#prebid-server-configuration)
9. [GDPR and Privacy](#gdpr-and-privacy)
10. [Lifecycle Management](#lifecycle-management)
11. [Multi-Process WebView](#multi-process-webview)
12. [Ad Refresh](#ad-refresh)
13. [ProGuard and R8](#proguard-and-r8)
14. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Minimum Version |
|---|---|
| Android Studio | Hedgehog (2023.1.1) or later |
| Kotlin | 1.9.0+ |
| `minSdk` | 21 (Android 5.0 Lollipop) |
| `compileSdk` | 34 |
| `targetSdk` | 34 |
| Gradle | 8.2+ |
| AGP (Android Gradle Plugin) | 8.1+ |

The SDK is written in pure Kotlin with no native (NDK) dependencies. It requires `kotlinx-coroutines-android` for the async listings API.

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
    implementation("com.sellwild:sellwild-sdk:1.0.0")

    // Required -- coroutines for async listings API
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

Sync your project and rebuild.

### Maven Local (offline or CI builds)

If you received the SDK as an `.aar` file, publish it to your local Maven repository:

```bash
# From the directory containing sellwild-sdk-1.0.0.aar
mvn install:install-file \
    -Dfile=sellwild-sdk-1.0.0.aar \
    -DgroupId=com.sellwild \
    -DartifactId=sellwild-sdk \
    -Dversion=1.0.0 \
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

## AndroidManifest Configuration

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

    private val config = SellwildConfig(
        partnerCode = "weatherbug",
        listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
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
| `onAdLoaded(adView)` | The ad creative has been fetched and rendered in the WebView. |
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
            listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
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

Use `SellwildAPIClient` to fetch marketplace listings and display them in a `RecyclerView`. Listing cards render natively -- no WebView involved.

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
        listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
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

1. The SDK renders a lightweight WebView containing a pre-configured Prebid.js instance.
2. Prebid.js is configured in S2S mode -- instead of running client-side bidder adapters, it sends a single OpenRTB 2.6 request to `prebid.sellwild.com/openrtb2/auction`.
3. Prebid Server fans out to all configured bidders in parallel, server-side.
4. The winning bid is returned and rendered in the WebView.

This architecture provides sub-200ms auction latency, eliminates client-side SDK bloat, and enables server-side bidder configuration changes without app updates.

### Available Bidders

The following SSPs are enabled on `prebid.sellwild.com`:

AppNexus/Xandr, PubMatic, Magnite/Rubicon, Index Exchange, OpenX, TripleLift, Sharethrough, InMobi, Smaato, Yieldmo, Unruly, Media.net, Sovrn, and 380+ additional adapters.

Contact sdk@sellwild.com to enable additional bidders for your account.

---

## GDPR and Privacy

The SDK supports IAB TCF v2 consent management. For users in GDPR regions, you must pass consent information obtained from your Consent Management Platform (CMP).

### Configuration

```kotlin
val config = SellwildConfig(
    partnerCode = "weatherbug",
    listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
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

`SellwildAdView` uses a WebView internally. Proper lifecycle management prevents memory leaks, background CPU usage, and ANR (Application Not Responding) errors.

### Why It Matters

- **WebView threads continue running when the Activity is paused.** JavaScript timers, network requests, and ad refresh cycles consume CPU and battery in the background.
- **WebView holds a reference to the Activity context.** If `destroy()` is not called in `onDestroy()`, the entire Activity and its view hierarchy will leak.
- **Orphaned WebViews can cause ANR.** On low-memory devices, a leaked WebView performing background work can starve the main thread.

### Required Lifecycle Calls

```kotlin
class AdActivity : AppCompatActivity() {

    private lateinit var adView: SellwildAdView

    override fun onResume() {
        super.onResume()
        adView.resume()   // Resumes WebView rendering and JavaScript execution
    }

    override fun onPause() {
        super.onPause()
        adView.pause()    // Pauses WebView, stops ad refresh timer
    }

    override fun onDestroy() {
        adView.destroy()  // Releases WebView resources, breaks context reference
        super.onDestroy()
    }
}
```

| Method | What It Does |
|---|---|
| `resume()` | Calls `WebView.onResume()`. Resumes JavaScript execution and rendering. |
| `pause()` | Calls `WebView.onPause()`. Suspends all JavaScript timers and ad refresh scheduling. |
| `destroy()` | Calls `pause()` then `WebView.destroy()`. Releases all WebView resources. The `SellwildAdView` instance must not be used after this call. |

For `SellwildWidgetView`, the same lifecycle pattern applies with identical `pause()`, `resume()`, and `destroy()` methods.

---

## Multi-Process WebView

On Android 9+ (API 28), creating a `WebView` from multiple processes that share the same data directory causes a crash (`android.webkit.WebViewFactory$MissingWebViewPackageException`). This affects apps that use multiple processes -- for example, a `:background` service process alongside the main UI process.

Call `SellwildWebViewCompat.configureForMultiProcess()` in your `Application.onCreate()`, before any `WebView` is created:

```kotlin
import com.sellwild.sdk.SellwildWebViewCompat

class MyApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // Must be called before any WebView is instantiated.
        // Sets a process-specific data directory suffix on API 28+.
        SellwildWebViewCompat.configureForMultiProcess(this)
    }
}
```

Register your Application class in `AndroidManifest.xml`:

```xml
<application
    android:name=".MyApplication"
    ... >
```

If your app is single-process, this call is a safe no-op.

---

## Ad Refresh

The SDK supports automatic ad refresh to maximize revenue from long-lived screens. After an impression is recorded, the SDK waits for the configured interval and then re-auctions the ad slot.

### Configuration

```kotlin
val config = SellwildConfig(
    partnerCode = "weatherbug",
    listingsUrl = "https://api.sellwild.com/widget/listings?partner=weatherbug",
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
# Sellwild SDK -- preserve JS bridge interface methods
-keepclassmembers class com.sellwild.sdk.SellwildAdView$SellwildJSBridge {
    @android.webkit.JavascriptInterface *;
}
-keepclassmembers class com.sellwild.sdk.SellwildWidgetView$WidgetJSBridge {
    @android.webkit.JavascriptInterface *;
}

# Preserve Listener interfaces for callback functionality
-keep interface com.sellwild.sdk.SellwildAdView$Listener { *; }
-keep interface com.sellwild.sdk.SellwildWidgetView$Listener { *; }

# Preserve data classes used in JSON serialization
-keepclassmembers class com.sellwild.sdk.SellwildConfig { *; }
-keepclassmembers class com.sellwild.sdk.PrebidServerConfig { *; }
-keepclassmembers class com.sellwild.sdk.SellwildListing { *; }
-keepclassmembers class com.sellwild.sdk.SellwildPhoto { *; }
-keepclassmembers class com.sellwild.sdk.SellwildUser { *; }

# Keep enum values used by the SDK
-keepclassmembers enum com.sellwild.sdk.AdSize {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
```

The `@JavascriptInterface` rules are critical. Without them, R8 strips the bridge methods and the WebView cannot communicate back to native code -- ad callbacks will silently stop working.

---

## Troubleshooting

### Cleartext Traffic Blocked

**Symptom:** Ads fail to render. Logcat shows `ERR_CLEARTEXT_NOT_PERMITTED` or `java.io.IOException: Cleartext HTTP traffic not permitted`.

**Cause:** Your app targets API 28+ and does not allow cleartext HTTP. Some ad creatives use HTTP URLs for tracking pixels.

**Fix:** Add a Network Security Config with domain exceptions for `doubleclick.net` and `googlesyndication.com`. See [AndroidManifest Configuration](#androidmanifest-configuration).

---

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

**Debug mode:** Set `debug = true` in your `SellwildConfig` to enable verbose Prebid.js logging in the WebView console. Attach Chrome DevTools to inspect the WebView:

```
chrome://inspect/#devices
```

---

### GDPR Consent Blocking Ads

**Symptom:** Ads load in the US but not in EU/EEA regions. No error callback fires.

**Cause:** Prebid Server enforces GDPR consent. If no TC string is provided for EU traffic, all bidders are excluded from the auction.

**Fix:** Ensure your CMP is initialized before loading ads. Read the consent string from `SharedPreferences` (key: `IABTCF_TCString`) and verify it is non-empty for EU users.

---

### ANR on Ad Load

**Symptom:** The app shows "Application Not Responding" when navigating to a screen with ads.

**Possible causes:**

| Cause | Resolution |
|---|---|
| Missing lifecycle calls | Ensure `pause()` and `destroy()` are called in `onPause()` and `onDestroy()`. Leaked WebViews consume main-thread resources. |
| WebView first init | The first `WebView` creation in an app session loads the WebView provider (Chrome/WebView APK). This can take 200-500ms on older devices. Avoid creating `SellwildAdView` during activity transitions. |
| Multi-process crash | Call `SellwildWebViewCompat.configureForMultiProcess()` in `Application.onCreate()`. See [Multi-Process WebView](#multi-process-webview). |

---

### WebView Crash on API 28+

**Symptom:** `android.webkit.WebViewFactory$MissingWebViewPackageException` or similar crash on app launch.

**Cause:** Multiple processes are sharing the same WebView data directory.

**Fix:** Call `SellwildWebViewCompat.configureForMultiProcess(this)` in `Application.onCreate()` before any other code that might instantiate a WebView.

---

### Ad Callbacks Not Firing (R8/ProGuard)

**Symptom:** Ads render visually but `onAdLoaded`, `onAdImpression`, and other callbacks never fire.

**Cause:** R8 has stripped the `@JavascriptInterface`-annotated bridge methods.

**Fix:** Add the ProGuard keep rules listed in [ProGuard and R8](#proguard-and-r8). Rebuild and verify.

---

## Support

- **Integration support:** sdk@sellwild.com
- **Documentation:** [Sellwild SDK Docs](https://github.com/sellwild/sellwild-sdk/tree/main/docs)
- **Prebid Server status:** [prebid.sellwild.com](https://prebid.sellwild.com)

---

Copyright 2026 Sellwild, Inc. All rights reserved.
