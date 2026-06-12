package com.sellwild.sdk

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Compose wrapper around [SellwildFeedView]. Renders the all-in-one native
 * feed (header + COL1-scheduled listings/ads) as a Composable.
 *
 * The row schedule, theme, ad zones, and partner URL all come from [config]
 * (which is populated from the CDN by [SellwildSDK.configure]). The
 * Composable itself just hosts the native view and forwards callbacks.
 */
@Composable
public fun SellwildFeed(
    config: SellwildConfig,
    modifier: Modifier = Modifier.fillMaxSize(),
    onListingTap: (SellwildListing) -> Boolean = { false },
    onAdImpression: (String) -> Unit = {},
    onAdClicked: (String) -> Unit = {},
    onLoad: () -> Unit = {},
    onError: (String) -> Unit = {},
) {
    val callbacks = remember(onListingTap, onAdImpression, onAdClicked, onLoad, onError) {
        object : SellwildFeedView.Listener {
            override fun onListingTap(listing: SellwildListing): Boolean = onListingTap(listing)
            override fun onAdImpression(zoneId: String) = onAdImpression(zoneId)
            override fun onAdClicked(zoneId: String) = onAdClicked(zoneId)
            override fun onLoad() = onLoad()
            override fun onError(message: String) = onError(message)
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            SellwildFeedView(ctx).apply {
                listener = callbacks
                setup(config)
                load()
            }
        },
        update = { view ->
            view.listener = callbacks
        },
    )
}
