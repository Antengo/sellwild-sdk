package com.sellwild.sdk.support

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.SellwildEventQueue
import com.sellwild.sdk.SellwildSDK
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * Emits payloads the SDK itself builds, so `node contracts/scripts/validate.mjs --out android`
 * (run by scripts/coverage/android.sh) checks real Android output against the schemas, not
 * just hand-made fixtures. [HttpStub] answers the POST, so no request leaves the JVM.
 *
 * Phase-3 tests emit their own variants (factory output, clientFailure events) with
 * [ContractEmitter.emit].
 */
@RunWith(RobolectricTestRunner::class)
class ContractOutputTest {

    @get:Rule
    val network = NetworkBlockRule()

    @Test
    fun `events queue body is emitted for validation`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val queue = SellwildEventQueue(context).apply { partnerCode = "sellwild-test" }
        // The shape SellwildAdView sends when GMA reports an error.
        queue.push("adError", "No ad to show.", "43")

        val requests = HttpStub.install { StubResponse(200) }.use { stub ->
            runBlocking { queue.flush() }
            stub.requests
        }

        assertEquals(1, requests.size)
        val request = requests[0]
        assertEquals("POST", request.method)
        assertEquals("https://events.sellwild.com/events/queue", request.url.toString())
        assertEquals("application/json", request.headers["Content-Type"])
        val batch = JSONArray(request.bodyText())
        assertEquals(1, batch.length())
        val event = batch.getJSONObject(0)
        assertEquals("adError", event.getString("event"))
        assertEquals("No ad to show.", event.getString("action"))
        assertEquals("43", event.getString("label"))
        assertEquals(queue.uid, event.getString("uid"))
        val attributes = event.getJSONObject("attributes")
        assertEquals(setOf("type", "sdkVersion", "code"), attributes.keys().asSequence().toSet())
        assertEquals("android", attributes.getString("type"))
        assertEquals(SellwildSDK.SDK_VERSION, attributes.getString("sdkVersion"))
        assertEquals("sellwild-test", attributes.getString("code"))
        ContractSchemas.assertValid("events-batch", request.bodyText())

        val file = ContractEmitter.emitText("events-batch", "sdk-ad-error", request.bodyText())

        assertEquals(File(ContractEmitter.outDir(), "events-batch.sdk-ad-error.json"), file)
        assertEquals(request.bodyText() + "\n", file.readText())
        assertTrue("the stub answered, so nothing reached the block", network.attempts.isEmpty())
    }
}
