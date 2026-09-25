package com.sellwild.sample

import android.app.Application
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sellwild.sdk.SellwildAPIClient
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildListing
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

/** The Listings screen's state: the cards and one line of status. */
data class ListingsState(
    val listings: List<SellwildListing> = emptyList(),
    val status: String = "Loading listings",
)

/**
 * Loads listings with `SellwildAPIClient` for an app that draws its own cards.
 * Refresh clears the client's cache and fetches again. The status counts loads:
 * "<count> listings, load <n>".
 */
class ListingsViewModel(app: Application) : AndroidViewModel(app) {
    private val client = SellwildAPIClient(app)
    private val stateFlow = MutableStateFlow(ListingsState())
    val state: StateFlow<ListingsState> = stateFlow.asStateFlow()
    private var loads = 0

    /** The first load, once: coming back to the tab keeps what was loaded. */
    fun loadOnce(config: SellwildConfig) {
        if (loads == 0) load(config, clearCache = false)
    }

    fun load(config: SellwildConfig, clearCache: Boolean) {
        if (clearCache) client.clearCache()
        loads += 1
        val load = loads
        stateFlow.update { it.copy(status = "Loading listings (load $load)") }
        viewModelScope.launch {
            client.fetchListings(config)
                .onSuccess { response ->
                    val status = "${response.listings.size} listings, load $load"
                    stateFlow.update { ListingsState(response.listings, status) }
                }
                .onFailure { error ->
                    // The SDK has already reported this failure; the app only shows it.
                    stateFlow.update { it.copy(status = "Listings failed (load $load): ${error.message}") }
                }
        }
    }
}

/** Listings: the listings API client and the app's own list of cards. */
@Composable
fun ListingsScreen(config: SellwildConfig, model: ListingsViewModel = viewModel()) {
    val state by model.state.collectAsState()
    val uriHandler = LocalUriHandler.current
    LaunchedEffect(config) { model.loadOnce(config) }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ScreenHeader(
                "Listings",
                "SellwildAPIClient.fetchListings, drawn by the app.",
                Modifier.weight(1f),
            )
            Button(
                onClick = { model.load(config, clearCache = true) },
                modifier = Modifier.padding(end = 16.dp).testTag(SampleIds.LISTINGS_REFRESH),
            ) {
                Text("Refresh")
            }
        }
        StatusLine(state.status, SampleIds.LISTINGS_STATUS)
        LazyColumn(Modifier.fillMaxSize().testTag(SampleIds.LISTINGS_LIST)) {
            // No key: a feed may repeat a listing id.
            items(state.listings) { listing ->
                ListingCard(
                    listing,
                    Modifier.clickable {
                        listing.tapUrl(config.partnerCode, config.bhTag)?.let(uriHandler::openUri)
                    },
                )
                HorizontalDivider()
            }
        }
    }
}

/** One listing: photo, title, price and seller. [io] reads and decodes the photo. */
@Composable
fun ListingCard(listing: SellwildListing, modifier: Modifier = Modifier, io: CoroutineDispatcher = Dispatchers.IO) {
    val url = listing.primaryPhotoUrl
    var photo by remember(url) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(url) {
        photo = url?.let { withContext(io) { decodePhoto(it) } }
    }
    Row(
        modifier.fillMaxWidth().testTag(SampleIds.LISTING_CARD).padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val thumb = Modifier.size(72.dp).clip(RoundedCornerShape(8.dp))
        photo?.let { Image(it, contentDescription = null, thumb, contentScale = ContentScale.Crop) }
            ?: Box(thumb.background(MaterialTheme.colorScheme.surfaceVariant))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                listing.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            listing.displayPrice?.let {
                Text("$$it", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
            }
            seller(listing)?.let {
                Text(
                    "by $it",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** "Nick P.", from the seller's first name and last initial. */
private fun seller(listing: SellwildListing): String? {
    val first = listing.user?.firstName?.trim().orEmpty().replaceFirstChar { it.uppercase() }
    val initial = listing.user?.lastName?.trim()?.firstOrNull()?.uppercaseChar()
    return when {
        first.isEmpty() -> null
        initial == null -> first
        else -> "$first $initial."
    }
}

/**
 * The feed's photos are data: URIs (AVIF, which Android 12 and later decode); others
 * are http(s). Null when the photo cannot be read: the card shows a grey square.
 */
private fun decodePhoto(url: String): ImageBitmap? = runCatching {
    val bytes = if (url.startsWith("data:")) {
        Base64.decode(url.substringAfter(','), Base64.DEFAULT)
    } else {
        URL(url).openStream().use { it.readBytes() }
    }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
}.getOrNull()
