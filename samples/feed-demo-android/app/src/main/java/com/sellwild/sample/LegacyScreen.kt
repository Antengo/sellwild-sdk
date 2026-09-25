package com.sellwild.sample

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildListing
import com.sellwild.sdk.SellwildWidgetView

/**
 * Legacy: the deprecated WebView widget. It runs Prebid.js in a WebView and cannot earn
 * the CPMs native ads do, so it is only on this screen. Do not copy it into a new app.
 */
@Composable
fun LegacyScreen(config: SellwildConfig) {
    var status by remember { mutableStateOf("Loading the widget") }
    val holder = remember { ViewHolder<SellwildWidgetView>() }
    PauseResumeEffect(onPause = { holder.view?.pause() }, onResume = { holder.view?.resume() })
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Text(
                "Legacy WebView widget (deprecated)",
                Modifier.testTag(SampleIds.LEGACY_TITLE),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "SellwildWidgetView. Use the Feed and Ads screens instead.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                status,
                Modifier.testTag(SampleIds.LEGACY_STATUS),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        // The id is on a Box around the widget: a test tag on an AndroidView does not
        // reach UI Automator.
        Box(Modifier.fillMaxSize().testTag(SampleIds.LEGACY_WEBVIEW)) {
            LegacyWidget(config, holder) { status = it }
        }
    }
}

/** `SellwildWidgetView` with its listener. [onStatus] gets its load and error lines. */
@Composable
private fun LegacyWidget(config: SellwildConfig, holder: ViewHolder<SellwildWidgetView>, onStatus: (String) -> Unit) {
    val status by rememberUpdatedState(onStatus)
    AndroidView(
        factory = { context ->
            SellwildWidgetView(context).apply {
                listener = object : SellwildWidgetView.Listener {
                    override fun onWidgetLoaded(widgetView: SellwildWidgetView) {
                        status("Widget loaded")
                    }

                    override fun onListingTapped(listing: SellwildListing) {
                        val url = listing.url ?: return
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    }

                    override fun onError(widgetView: SellwildWidgetView, message: String) {
                        status("Widget error: $message")
                    }
                }
                setup(config)
                load()
                holder.view = this
            }
        },
        modifier = Modifier.fillMaxSize(),
        onRelease = { it.destroy() },
    )
}
