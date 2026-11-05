package com.sellwild.sdk

import android.view.View
import android.view.ViewGroup
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.sellwild.sdk.core.ListingsParser
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The Compose wrapper (SellwildFeed) on Robolectric: it hosts a SellwildFeedView that sets up
 * and loads the config it is given, and forwards the view's callbacks to the current lambdas.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildFeedComposeTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    @get:Rule
    val ads = AdNetworkRule()

    private val listingsUrl = "https://cache.sellwild.com/listings-img-data-sm-fixture"

    /** The lifecycle and saved state a ComponentActivity would give a ComposeView. */
    private class Host : LifecycleOwner, SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val saved = SavedStateRegistryController.create(this)
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry

        init {
            saved.performRestore(null)
            registry.currentState = Lifecycle.State.RESUMED
        }
    }

    @Before
    fun setUp() {
        CapturedEvents().install()
        SellwildFeedView.apiClient = { ctx -> SellwildAPIClient(ctx, Dispatchers.Unconfined) { } }
        FeedImages.io = Dispatchers.Unconfined
        FeedImages.fetch = { pixel() }
    }

    private fun View.feedView(): SellwildFeedView? = when (this) {
        is SellwildFeedView -> this
        is ViewGroup -> childrenList().firstNotNullOfOrNull { it.feedView() }
        else -> null
    }

    @Test
    fun `the wrapper hosts a feed that loads its config and forwards every callback`() {
        val calls = mutableListOf<String>()
        var consume = true
        val onLoad = mutableStateOf({ calls += "load" })
        val activity = newActivity()
        val host = Host()
        val compose = ComposeView(activity).apply {
            setViewTreeLifecycleOwner(host)
            setViewTreeSavedStateRegistryOwner(host)
        }
        val body = ListingsResponseFactory.withItems(ListingFactory.checked()).toString()

        HttpStub.install { StubResponse(200, body) }.use {
            activity.setContentView(compose, ViewGroup.LayoutParams(1080, 1920))
            compose.setContent {
                SellwildFeed(
                    config = configWith("LISTINGS" to listingsUrl, "COL1" to "L"),
                    onListingTap = { calls += "tap:${it.id}"; consume },
                    onAdImpression = { calls += "impression:$it" },
                    onAdClicked = { calls += "clicked:$it" },
                    onLoad = onLoad.value,
                    onError = { calls += "error:$it" },
                )
            }
            idleFor(200)
        }

        val feed = checkNotNull(compose.feedView())
        assertEquals(listOf("load"), calls)
        val listener = checkNotNull(feed.listener)
        val listing = ListingsParser.parseListing(ListingFactory.checked())
        assertTrue(listener.onListingTap(listing))
        consume = false
        assertFalse(listener.onListingTap(listing))
        listener.onAdImpression("z1")
        listener.onAdClicked("z1")
        listener.onError("boom")

        // A new onLoad lambda reaches the same view on recomposition.
        onLoad.value = { calls += "load again" }
        idleFor(200)
        checkNotNull(feed.listener).onLoad()

        assertEquals(
            listOf("load", "tap:105140231", "tap:105140231", "impression:z1", "clicked:z1", "error:boom", "load again"),
            calls,
        )
    }

    @Test
    fun `the default callbacks do nothing`() {
        val activity = newActivity()
        val host = Host()
        val compose = ComposeView(activity).apply {
            setViewTreeLifecycleOwner(host)
            setViewTreeSavedStateRegistryOwner(host)
        }
        val body = ListingsResponseFactory.withItems(ListingFactory.checked()).toString()

        HttpStub.install { StubResponse(200, body) }.use {
            activity.setContentView(compose, ViewGroup.LayoutParams(1080, 1920))
            compose.setContent { SellwildFeed(config = configWith("LISTINGS" to listingsUrl, "COL1" to "L")) }
            idleFor(200)
        }

        val listener = checkNotNull(checkNotNull(compose.feedView()).listener)
        assertFalse(listener.onListingTap(ListingsParser.parseListing(ListingFactory.checked())))
        listener.onAdImpression("z1")
        listener.onAdClicked("z1")
        listener.onLoad()
        listener.onError("boom")
    }

    @Test
    fun `a parent that recomposes with the same arguments keeps the same feed view`() {
        val activity = newActivity()
        val host = Host()
        val compose = ComposeView(activity).apply {
            setViewTreeLifecycleOwner(host)
            setViewTreeSavedStateRegistryOwner(host)
        }
        val body = ListingsResponseFactory.withItems(ListingFactory.checked()).toString()
        val config = configWith("LISTINGS" to listingsUrl, "COL1" to "L")
        val calls = mutableListOf<String>()
        val onListingTap: (SellwildListing) -> Boolean = { false }
        val onAdImpression: (String) -> Unit = { calls += "impression:$it" }
        val onAdClicked: (String) -> Unit = { calls += "clicked:$it" }
        val onLoad: () -> Unit = { calls += "load" }
        val onError: (String) -> Unit = { calls += "error:$it" }
        val modifier = androidx.compose.ui.Modifier
        val tick = mutableStateOf(0)

        HttpStub.install { StubResponse(200, body) }.use {
            activity.setContentView(compose, ViewGroup.LayoutParams(1080, 1920))
            compose.setContent {
                // Reading tick makes this content recompose; the feed's arguments stay the same.
                calls += "compose:${tick.value}"
                SellwildFeed(config, modifier, onListingTap, onAdImpression, onAdClicked, onLoad, onError)
            }
            idleFor(200)
            val feed = checkNotNull(compose.feedView())

            tick.value = 1
            idleFor(200)

            assertTrue(feed === compose.feedView())
        }

        assertEquals(listOf("compose:0", "load", "compose:1"), calls)
    }

    private val LocalTick = androidx.compose.runtime.compositionLocalOf { 0 }

    @Test
    fun `a parent whose composition local changes recomposes the wrapper onto the same view and listener`() {
        val activity = newActivity()
        val host = Host()
        val compose = ComposeView(activity).apply {
            setViewTreeLifecycleOwner(host)
            setViewTreeSavedStateRegistryOwner(host)
        }
        val body = ListingsResponseFactory.withItems(ListingFactory.checked()).toString()
        val config = configWith("LISTINGS" to listingsUrl, "COL1" to "L")
        val onListingTap: (SellwildListing) -> Boolean = { false }
        val onAdImpression: (String) -> Unit = {}
        val onAdClicked: (String) -> Unit = {}
        val onLoad: () -> Unit = {}
        val onError: (String) -> Unit = {}
        val tick = mutableStateOf(0)

        HttpStub.install { StubResponse(200, body) }.use {
            activity.setContentView(compose, ViewGroup.LayoutParams(1080, 1920))
            compose.setContent {
                androidx.compose.runtime.CompositionLocalProvider(LocalTick provides tick.value) {
                    SellwildFeed(config, androidx.compose.ui.Modifier, onListingTap, onAdImpression, onAdClicked, onLoad, onError)
                }
            }
            idleFor(200)
            val feed = checkNotNull(compose.feedView())
            val listener = feed.listener

            tick.value = 1
            idleFor(200)

            assertTrue(feed === compose.feedView())
            assertTrue(listener === feed.listener)
        }
    }

    @Test
    fun `a composable that forwards its own arguments hosts the feed and keeps it across recompositions`() {
        val activity = newActivity()
        val host = Host()
        val compose = ComposeView(activity).apply {
            setViewTreeLifecycleOwner(host)
            setViewTreeSavedStateRegistryOwner(host)
        }
        val body = ListingsResponseFactory.withItems(ListingFactory.checked()).toString()
        val first = configWith("LISTINGS" to listingsUrl, "COL1" to "L")
        val config = mutableStateOf(first)
        val calls = mutableListOf<String>()
        val onLoad: () -> Unit = { calls += "load" }

        HttpStub.install { StubResponse(200, body) }.use {
            activity.setContentView(compose, ViewGroup.LayoutParams(1080, 1920))
            compose.setContent { ForwardingFeed(config.value, onLoad) }
            idleFor(200)
            val feed = checkNotNull(compose.feedView())

            config.value = configWith("LISTINGS" to listingsUrl, "COL1" to "LL")
            idleFor(200)

            assertTrue(feed === compose.feedView())
        }

        assertEquals(listOf("load"), calls)
    }
}

/** A host composable that passes its own parameters on, so the wrapper learns whether they changed. */
@androidx.compose.runtime.Composable
private fun ForwardingFeed(config: SellwildConfig, onLoad: () -> Unit) {
    SellwildFeed(config = config, onLoad = onLoad)
}
