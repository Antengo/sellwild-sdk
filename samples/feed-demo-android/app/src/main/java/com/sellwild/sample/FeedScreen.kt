package com.sellwild.sample

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildFeed

/**
 * Feed: `SellwildFeed`, the all-in-one native feed. Listing cards with native ads
 * between them, laid out by the config's COL1 schedule. It opens first.
 */
@Composable
fun FeedScreen(config: SellwildConfig) {
    var status by remember { mutableStateOf("Loading the feed") }
    var impressions by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("Feed", "SellwildFeed: native listings with native ads between them.")
        StatusLine(status, SampleIds.FEED_STATUS)
        // The id is on a Box around the feed: a test tag on an AndroidView (which
        // SellwildFeed is) does not reach UI Automator.
        Box(Modifier.fillMaxSize().testTag(SampleIds.FEED_LIST)) {
            SellwildFeed(
                config = config,
                modifier = Modifier.fillMaxSize(),
                // false: the SDK opens the listing in a Custom Tab.
                onListingTap = { false },
                onAdImpression = {
                    impressions += 1
                    status = "Feed loaded, $impressions ad impression(s)"
                },
                onLoad = { status = "Feed loaded" },
                onError = { message -> status = "Feed error: $message" },
            )
        }
    }
}
