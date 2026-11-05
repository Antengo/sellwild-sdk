package com.sellwild.sample

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sellwild.sdk.SellwildConfig

/** The four tabs, in the order and with the titles every platform's sample uses. */
enum class SampleTab(val title: String, val id: String, val icon: ImageVector) {
    Feed("Feed", SampleIds.TAB_FEED, Icons.Filled.Home),
    Ads("Ads", SampleIds.TAB_ADS, Icons.Filled.Star),
    Listings("Listings", SampleIds.TAB_LISTINGS, Icons.AutoMirrored.Filled.List),
    Diagnostics("Diagnostics", SampleIds.TAB_DIAGNOSTICS, Icons.Filled.Info),
}

/** Waits for `SellwildSDK.configure`, then shows the tabs. */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SampleApp(model: SampleViewModel = viewModel()) {
    val config by model.config.collectAsState()
    MaterialTheme {
        // testTagsAsResourceId: UI Automator (Maestro) reads each testTag as a resource-id.
        Surface(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
            val ready = config
            if (ready == null) {
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator()
                    Text("Loading Sellwild config", Modifier.padding(top = 12.dp))
                }
            } else {
                SampleTabs(ready)
            }
        }
    }
}

/** A bottom navigation bar. Each tab button carries its e2e id; the flows tap them by id. */
@Composable
fun SampleTabs(config: SellwildConfig) {
    var tab by rememberSaveable { mutableStateOf(SampleTab.Feed) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                SampleTab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = item == tab,
                        onClick = { tab = item },
                        icon = { Icon(item.icon, contentDescription = null) },
                        // labelSmall: "Diagnostics" fits a fifth of a phone's width.
                        label = { Text(item.title, maxLines = 1, style = MaterialTheme.typography.labelSmall) },
                        modifier = Modifier.testTag(item.id),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                SampleTab.Feed -> FeedScreen(config)
                SampleTab.Ads -> AdsScreen(config)
                SampleTab.Listings -> ListingsScreen(config)
                SampleTab.Diagnostics -> DiagnosticsScreen(config)
            }
        }
    }
}

/** The title block at the top of each screen. */
@Composable
fun ScreenHeader(title: String, detail: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** One line of status under a screen's header, with its e2e id. */
@Composable
fun StatusLine(text: String, id: String) {
    Text(
        text,
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp).testTag(id),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/**
 * Calls [onPause] and [onResume] with the screen's lifecycle, as an Activity would
 * call an SDK view's pause() and resume().
 */
@Composable
fun PauseResumeEffect(onPause: () -> Unit, onResume: () -> Unit) {
    val owner = LocalLifecycleOwner.current
    val pause by rememberUpdatedState(onPause)
    val resume by rememberUpdatedState(onResume)
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> pause()
                Lifecycle.Event.ON_RESUME -> resume()
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
}

/** Holds an SDK view an AndroidView made, for callbacks outside the factory. */
class ViewHolder<T : Any> {
    var view: T? = null
}
