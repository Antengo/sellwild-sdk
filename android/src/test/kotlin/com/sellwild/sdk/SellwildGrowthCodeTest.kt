package com.sellwild.sdk

import android.content.Context
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import com.sellwild.sdk.factories.AppConfigFactory
import com.sellwild.sdk.factories.EidBlobFactory
import com.sellwild.sdk.factories.GrowthCodeSyncResponseFactory
import com.sellwild.sdk.failures.FailuresRule
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailures
import com.sellwild.sdk.support.CapturedRequest
import com.sellwild.sdk.support.FixtureLoader
import com.sellwild.sdk.support.HttpStub
import com.sellwild.sdk.support.NetworkBlockRule
import com.sellwild.sdk.support.StubResponse
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Stands in for Play Services' AdvertisingIdClient, which SellwildGrowthCode reaches by reflection. */
object FakeAdvertisingIdClient {
    class Info(private val id: String?, private val limited: Boolean) {
        fun getId(): String? = id
        fun isLimitAdTrackingEnabled(): Boolean = limited
    }

    @Volatile
    var next: Info? = null

    @JvmStatic
    fun getAdvertisingIdInfo(@Suppress("UNUSED_PARAMETER") context: Context): Info? = next
}

/** An advertising id client whose getters return unexpected types. */
object OddAdvertisingIdClient {
    class Info {
        fun getId(): Any = 42
        fun isLimitAdTrackingEnabled(): Any = "no"
    }

    @JvmStatic
    fun getAdvertisingIdInfo(@Suppress("UNUSED_PARAMETER") context: Context): Info = Info()
}

/**
 * GrowthCode on Android: settings resolution, the once-per-launch sync with its throttle, the
 * persisted gc_id / eb, and every failure reported once (growthcode.*). The sync runs inline
 * with an injected clock and advertising id except where a test proves the defaults; the
 * GrowthCode endpoint is answered in-process by [HttpStub] and never called for real.
 */
@RunWith(RobolectricTestRunner::class)
class SellwildGrowthCodeTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val failures = FailuresRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val prefs: SharedPreferences get() = context.getSharedPreferences("sellwild_sdk", Context.MODE_PRIVATE)
    private val now = 1_790_000_000_000L
    private val hour = 3_600_000L
    private val maid = "38400000-8cf0-11bd-b23e-10b96e40000d"
    private lateinit var events: CapturedEvents

    private val enabled = mapOf(
        "GROWTHCODE_ENABLED" to true,
        "GROWTHCODE_PARTNER_ID" to "pid-1",
        "GROWTHCODE_SYNC_URL" to "https://weatherbug.com/app",
    )

    @Before
    fun setUp() {
        SellwildGrowthCode.resetForTesting()
        SellwildGrowthCode.runner = { it.run() }
        SellwildGrowthCode.clock = { now }
        SellwildGrowthCode.advertisingIdSource = { maid to "GAID" }
        prefs.edit().clear().commit()
        events = CapturedEvents().install()
    }

    @After
    fun tearDown() {
        SellwildGrowthCode.resetForTesting()
        FakeAdvertisingIdClient.next = null
        SellwildEidRegistry.setGrowthCode(emptyList())
    }

    private fun config(overrides: Map<String, Any?> = enabled, local: SellwildGrowthCodeConfig? = null) =
        SellwildConfig(partnerCode = "weatherbug", remoteJson = AppConfigFactory.checked(overrides).toString(), growthCode = local)

    /** One resolveIfNeeded with the endpoint answering [response]; the requests it sent. */
    private fun sync(response: StubResponse?, config: SellwildConfig = config()): List<CapturedRequest> =
        HttpStub.install { response }.use { stub ->
            SellwildGrowthCode.resolveIfNeeded(context, config, "43")
            stub.requests
        }

    // ── resolve ──────────────────────────────────────────────────────────────

    @Test
    fun `settings default to off, with the hosted endpoint, MAID on and a 48 hour TTL`() {
        val settings = SellwildGrowthCode.resolve(SellwildConfig(partnerCode = "weatherbug"), "43")

        assertEquals(
            SellwildGrowthCode.Settings(false, null, "https://ids.api.gcprivacy.id/v4/sync/api", null, true, 48.0),
            settings,
        )
    }

    @Test
    fun `remote keys set every field, and the zone map turns it on when the global flag does not`() {
        val remote = FixtureLoader.jsonObject("fixtures/app-config/valid/flags-mixed-types.json")
        val settings = SellwildGrowthCode.resolve(SellwildConfig(partnerCode = "fixture", remoteJson = remote.toString()), null)
        val byZone = config(mapOf("GROWTHCODE_ENABLED" to "0", "GROWTHCODE_ENABLED_BY_ZONE" to JSONObject().put("43", "1")))
        val full = config(
            mapOf(
                "GROWTHCODE_PARTNER_ID" to "pid-1",
                "GROWTHCODE_ENDPOINT" to "https://gc.invalid/sync",
                "GROWTHCODE_SYNC_URL" to "weatherbug.com",
                "GROWTHCODE_TTL_HOURS" to 12,
            ),
        )

        assertTrue(settings.enabled)
        assertFalse("GROWTHCODE_SEND_MAID: no", settings.sendMaid)
        assertEquals(24.0, settings.ttlHours, 0.0)
        assertTrue(SellwildGrowthCode.resolve(byZone, "43").enabled)
        assertFalse(SellwildGrowthCode.resolve(byZone, "280").enabled)
        assertFalse(SellwildGrowthCode.resolve(byZone, null).enabled)
        assertEquals(
            SellwildGrowthCode.Settings(false, "pid-1", "https://gc.invalid/sync", "weatherbug.com", true, 12.0),
            SellwildGrowthCode.resolve(full, "43"),
        )
    }

    @Test
    fun `every local field wins over the remote key`() {
        val local = SellwildGrowthCodeConfig(
            enabled = false,
            partnerId = "local-pid",
            endpoint = "https://local.invalid/sync",
            syncUrl = "local.example",
            sendMaid = false,
            ttlHours = 1,
        )

        assertEquals(
            SellwildGrowthCode.Settings(false, "local-pid", "https://local.invalid/sync", "local.example", false, 1.0),
            SellwildGrowthCode.resolve(config(local = local), "43"),
        )
        assertTrue(SellwildGrowthCode.resolve(config(emptyMap(), SellwildGrowthCodeConfig(enabled = true, sendMaid = true)), "43").sendMaid)
    }

    @Test
    fun `config that does not parse is reported and GrowthCode stays off`() {
        val bad = SellwildConfig(partnerCode = "weatherbug", remoteJson = FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"))

        assertFalse(SellwildGrowthCode.resolve(bad, "43").enabled)

        assertEquals(listOf(SellwildFailureCode.CONFIG_REMOTE_VALUES_PARSE), events.codes)
    }

    // ── resolveIfNeeded ──────────────────────────────────────────────────────

    @Test
    fun `off means no sync and nothing reported`() {
        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200), config(emptyMap())))
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `on without a partner id is growthcode config missing, once per launch`() {
        val noPartner = config(mapOf("GROWTHCODE_ENABLED" to true, "GROWTHCODE_SYNC_URL" to "weatherbug.com"))

        // Every ad view load calls resolveIfNeeded with the same config.
        repeat(3) { assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200), noPartner)) }

        val event = events.single(SellwildFailureCode.GROWTHCODE_CONFIG_MISSING)
        assertEquals("growthcode", event.getString("label"))
        assertEquals("no partner id", event.getJSONObject("attributes").getString("msg"))
        assertEquals("43", event.getJSONObject("attributes").getString("zoneId"))
        assertEquals("a complete config still syncs", 1, sync(StubResponse(200, GrowthCodeSyncResponseFactory.checked().toString())).size)
    }

    @Test
    fun `on without a sync url is growthcode config missing too`() {
        sync(null, config(mapOf("GROWTHCODE_ENABLED" to true, "GROWTHCODE_PARTNER_ID" to "pid-1", "GROWTHCODE_SYNC_URL" to "")))

        assertEquals("no sync url", events.attributes(SellwildFailureCode.GROWTHCODE_CONFIG_MISSING).getString("msg"))
    }

    @Test
    fun `a first sync posts the form, then saves gc_id, eb and the time, and feeds the eids`() {
        val requests = sync(StubResponse(200, GrowthCodeSyncResponseFactory.checked().toString()))

        val request = requests.single()
        assertEquals("POST", request.method)
        assertEquals("https://ids.api.gcprivacy.id/v4/sync/api?pid=pid-1&u=https%3A%2F%2Fweatherbug.com%2Fapp", request.url.toString())
        assertEquals("application/x-www-form-urlencoded", request.headers["Content-Type"])
        assertEquals("h=weatherbug.com&maid=$maid&maid_type=GAID", request.bodyText())
        assertEquals("gc-fixture-0001", prefs.getString("_sw_gc_id.pid-1", null))
        assertEquals(GrowthCodeSyncResponseFactory.checked().getString("eb"), prefs.getString("_sw_gc_eb.pid-1", null))
        assertEquals(now, prefs.getLong("_sw_gc_synced_at.pid-1", -1))
        assertEquals(emptyList<String>(), events.codes)
        assertEquals("a hand-built config names the failure partner", "weatherbug", SellwildFailures.context.partnerCode)
    }

    @Test
    fun `the sync runs once per launch`() {
        val response = StubResponse(200, GrowthCodeSyncResponseFactory.checked().toString())

        assertEquals(1, sync(response).size)
        assertEquals(0, sync(response).size)
    }

    @Test
    fun `cached eids that parse to nothing are not fed`() {
        prefs.edit()
            .putString("_sw_gc_id.pid-1", "gc-1")
            .putLong("_sw_gc_synced_at.pid-1", now - hour)
            .putString("_sw_gc_eb.pid-1", EidBlobFactory.variant("empty").toString())
            .commit()

        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200)))
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `a sync status below 200 is growthcode sync http too`() {
        sync(StubResponse(199))

        assertEquals("199", events.attributes(SellwildFailureCode.GROWTHCODE_SYNC_HTTP).getString("httpStatus"))
    }

    @Test
    fun `inside the TTL the cached eids are replayed and nothing is posted`() {
        prefs.edit()
            .putString("_sw_gc_id.pid-1", "gc-1")
            .putLong("_sw_gc_synced_at.pid-1", now - hour)
            .putString("_sw_gc_eb.pid-1", EidBlobFactory.base().toString())
            .commit()

        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200)))
        assertEquals(emptyList<String>(), events.codes)
    }

    @Test
    fun `after the TTL the stored gc_id is sent`() {
        prefs.edit().putString("_sw_gc_id.pid-1", "gc-1").putLong("_sw_gc_synced_at.pid-1", now - 49 * hour).commit()

        val request = sync(StubResponse(200, GrowthCodeSyncResponseFactory.variant("empty").toString())).single()

        assertEquals("gcid=gc-1&h=weatherbug.com&maid=$maid&maid_type=GAID", request.bodyText())
        assertEquals("gc-1", prefs.getString("_sw_gc_id.pid-1", null))
        assertEquals(now, prefs.getLong("_sw_gc_synced_at.pid-1", -1))
    }

    @Test
    fun `with MAID sending off, a device without an id skips the call`() {
        SellwildGrowthCode.advertisingIdSource = { null }

        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200), config(enabled + ("GROWTHCODE_SEND_MAID" to false))))
    }

    // GROWTHCODE_SEND_MAID is default-on when unset, but a set value is on only for an on
    // word (1, true, yes, on), as core's truthy() reads it: other text turns it off.
    @Test
    fun `MAID sending set to text that is not an on word is off, so a device without an id skips the call`() {
        SellwildGrowthCode.advertisingIdSource = { null }
        val config = config(enabled + ("GROWTHCODE_SEND_MAID" to "enabled"))

        assertFalse(SellwildGrowthCode.resolve(config, "43").sendMaid)
        assertTrue(SellwildGrowthCode.resolve(config(enabled + ("GROWTHCODE_SEND_MAID" to "Yes")), "43").sendMaid)
        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200), config))
    }

    @Test
    fun `without an id but with MAID sending on, the call goes out without one`() {
        SellwildGrowthCode.advertisingIdSource = { null }

        assertEquals("h=weatherbug.com", sync(StubResponse(200, GrowthCodeSyncResponseFactory.variant("empty").toString())).single().bodyText())
    }

    // A9: org.json on a device reads JSON null as the text "null", so a response with
    // "gc_id": null stored the gc_id "null" and sent gcid=null on every later sync.
    @Test
    fun `this runtime has the device org json`() {
        assertEquals("null", JSONObject("""{"a":null}""").optString("a"))
    }

    @Test
    fun `a JSON null gc_id or eb is not stored as the text null`() {
        sync(StubResponse(200, GrowthCodeSyncResponseFactory.nullIds().toString()))

        assertNull(prefs.getString("_sw_gc_id.pid-1", null))
        assertNull(prefs.getString("_sw_gc_eb.pid-1", null))
        assertEquals(now, prefs.getLong("_sw_gc_synced_at.pid-1", -1))
        assertEquals("nothing to parse, nothing to report", emptyList<String>(), events.codes)
    }

    // A9, the same bug in the remote keys: a JSON null partner id, endpoint or sync url read
    // as the text "null", so GrowthCode ran with pid=null against the host "null".
    @Test
    fun `a JSON null partner id, endpoint or sync url is unset, not the text null`() {
        val nulls = SellwildConfig(
            partnerCode = "weatherbug",
            remoteJson = AppConfigFactory.offSchema(
                mapOf(
                    "GROWTHCODE_ENABLED" to true,
                    "GROWTHCODE_PARTNER_ID" to JSONObject.NULL,
                    "GROWTHCODE_ENDPOINT" to JSONObject.NULL,
                    "GROWTHCODE_SYNC_URL" to JSONObject.NULL,
                ),
            ).toString(),
        )

        assertEquals(
            SellwildGrowthCode.Settings(true, null, "https://ids.api.gcprivacy.id/v4/sync/api", null, true, 48.0),
            SellwildGrowthCode.resolve(nulls, "43"),
        )
        assertEquals("no request to a host named null", emptyList<CapturedRequest>(), sync(StubResponse(200), nulls))
        assertEquals("no partner id", events.attributes(SellwildFailureCode.GROWTHCODE_CONFIG_MISSING).getString("msg"))
    }

    @Test
    fun `a non-2xx sync is growthcode sync http, and the throttle is not saved`() {
        sync(StubResponse(503))

        val attributes = events.attributes(SellwildFailureCode.GROWTHCODE_SYNC_HTTP)
        assertEquals("503", attributes.getString("httpStatus"))
        assertEquals("HTTP 503", attributes.getString("msg"))
        assertEquals("ids.api.gcprivacy.id", attributes.getString("host"))
        assertEquals("warn", attributes.getString("severity"))
        assertFalse(prefs.contains("_sw_gc_synced_at.pid-1"))
    }

    @Test
    fun `a response that is not JSON is growthcode sync parse, and the throttle is not saved`() {
        sync(StubResponse(200, FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml")))

        assertEquals("JSONException", events.attributes(SellwildFailureCode.GROWTHCODE_SYNC_PARSE).getString("errName"))
        assertFalse(prefs.contains("_sw_gc_synced_at.pid-1"))
    }

    @Test
    fun `an eb that is not a JSON array is growthcode eid parse, and the response is still saved`() {
        val response = GrowthCodeSyncResponseFactory.checked(mapOf("eb" to EidBlobFactory.variant("not-an-array").toString()))

        sync(StubResponse(200, response.toString()))

        assertEquals("JSONException", events.attributes(SellwildFailureCode.GROWTHCODE_EID_PARSE).getString("errName"))
        assertEquals("gc-fixture-0001", prefs.getString("_sw_gc_id.pid-1", null))
    }

    @Test
    fun `a bad cached eb that the sync sends again is reported once`() {
        val eb = EidBlobFactory.variant("partly-invalid").toString()
        prefs.edit()
            .putString("_sw_gc_id.pid-1", "gc-1")
            .putLong("_sw_gc_synced_at.pid-1", now - 49 * hour)
            .putString("_sw_gc_eb.pid-1", eb)
            .commit()

        sync(StubResponse(200, GrowthCodeSyncResponseFactory.checked(mapOf("eb" to eb)).toString())).single()

        assertEquals("dropped 4 of 6 entries and 3 uids", events.attributes(SellwildFailureCode.GROWTHCODE_EID_INVALID).getString("msg"))
        assertEquals(eb, prefs.getString("_sw_gc_eb.pid-1", null))
        assertEquals(now, prefs.getLong("_sw_gc_synced_at.pid-1", -1))
    }

    @Test
    fun `a bad cached eb and a different bad new eb are each reported`() {
        prefs.edit()
            .putString("_sw_gc_id.pid-1", "gc-1")
            .putLong("_sw_gc_synced_at.pid-1", now - 49 * hour)
            .putString("_sw_gc_eb.pid-1", EidBlobFactory.variant("not-an-array").toString())
            .commit()
        val fresh = EidBlobFactory.variant("partly-invalid").toString()

        sync(StubResponse(200, GrowthCodeSyncResponseFactory.checked(mapOf("eb" to fresh)).toString())).single()

        assertEquals(listOf(SellwildFailureCode.GROWTHCODE_EID_PARSE, SellwildFailureCode.GROWTHCODE_EID_INVALID), events.codes)
        assertEquals(fresh, prefs.getString("_sw_gc_eb.pid-1", null))
    }

    @Test
    fun `a request that fails is growthcode sync network`() {
        network.expectAttempts()

        sync(null)

        assertEquals(1, network.attempts.size)
        val attributes = events.attributes(SellwildFailureCode.GROWTHCODE_SYNC_NETWORK)
        assertEquals("NetworkBlockedException", attributes.getString("errName"))
        assertEquals("ids.api.gcprivacy.id", attributes.getString("host"))
    }

    @Test
    fun `a stored value of the wrong type is growthcode sync exception, not network`() {
        prefs.edit().putLong("_sw_gc_eb.pid-1", 7L).commit()

        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200)))

        val attributes = events.attributes(SellwildFailureCode.GROWTHCODE_SYNC_EXCEPTION)
        assertEquals("ClassCastException", attributes.getString("errName"))
        assertEquals("warn", attributes.getString("severity"))
    }

    @Test
    fun `an endpoint that is not http(s) is growthcode url invalid`() {
        assertEquals(emptyList<CapturedRequest>(), sync(StubResponse(200), config(enabled + ("GROWTHCODE_ENDPOINT" to "ftp://gc.invalid/sync"))))

        assertEquals("not an http(s) URL: ftp", events.attributes(SellwildFailureCode.GROWTHCODE_URL_INVALID).getString("msg"))
    }

    // A9 again: a JSON null eid source, uid id or stype was kept as the text "null" and sent
    // to every auction as an eid.
    @Test
    fun `a JSON null eid source, id or stype is dropped, not sent as the text null`() {
        val eids = SellwildGrowthCode.parseEidBlob(EidBlobFactory.variant("null-text-fields").toString())

        assertEquals(
            listOf(SellwildEid("id5-sync.com", listOf(SellwildEidUid("ID5*fixture", 1), SellwildEidUid("ppid-fixture", 0)))),
            eids,
        )
        assertEquals("dropped 2 of 3 entries and 1 uids", events.attributes(SellwildFailureCode.GROWTHCODE_EID_INVALID).getString("msg"))
    }

    @Test
    fun `parseEidBlob keeps what is usable and reports what is not`() {
        assertEquals(2, SellwildGrowthCode.parseEidBlob(EidBlobFactory.base().toString()).size)
        assertEquals(2, SellwildGrowthCode.parseEidBlob(EidBlobFactory.variant("partly-invalid").toString()).size)

        assertEquals(listOf(SellwildFailureCode.GROWTHCODE_EID_INVALID), events.codes)
    }

    @Test
    fun `shouldSync reads the injected clock`() {
        assertTrue(SellwildGrowthCode.shouldSync("gc-1", now - 48 * hour, 48.0))
        assertFalse(SellwildGrowthCode.shouldSync("gc-1", now - hour, 48.0))
    }

    // ── advertising id ───────────────────────────────────────────────────────

    @Test
    fun `the advertising id is read by reflection, and only a real one is used`() {
        val fake = FakeAdvertisingIdClient::class.java.name

        FakeAdvertisingIdClient.next = FakeAdvertisingIdClient.Info(maid, limited = false)
        assertEquals(maid to "GAID", SellwildGrowthCode.advertisingId(context, fake))
        FakeAdvertisingIdClient.next = FakeAdvertisingIdClient.Info(maid, limited = true)
        assertNull(SellwildGrowthCode.advertisingId(context, fake))
        FakeAdvertisingIdClient.next = FakeAdvertisingIdClient.Info(null, limited = false)
        assertNull(SellwildGrowthCode.advertisingId(context, fake))
        FakeAdvertisingIdClient.next = null
        assertNull(SellwildGrowthCode.advertisingId(context, fake))
        assertNull("getters of other types", SellwildGrowthCode.advertisingId(context, OddAdvertisingIdClient::class.java.name))
        assertNull("no Play Services client class", SellwildGrowthCode.advertisingId(context, "com.example.NoSuchClient"))
        assertEquals("never reported (privacy)", emptyList<String>(), events.codes)
    }

    @Test
    fun `by default the sync runs on a daemon thread with the real clock and Play Services id`() {
        SellwildGrowthCode.resetForTesting()

        val request = HttpStub.install { StubResponse(200, GrowthCodeSyncResponseFactory.checked().toString()) }.use { stub ->
            SellwildGrowthCode.resolveIfNeeded(context, config(), "43")
            val deadline = System.currentTimeMillis() + 20_000
            while (!prefs.contains("_sw_gc_synced_at.pid-1") && System.currentTimeMillis() < deadline) Thread.sleep(10)
            stub.requests.single()
        }

        assertEquals("no Play Services on the test JVM, so no MAID", "h=weatherbug.com", request.bodyText())
        val saved = prefs.getLong("_sw_gc_synced_at.pid-1", -1)
        assertTrue("the real clock: $saved", saved in (System.currentTimeMillis() - 60_000)..System.currentTimeMillis())
    }
}
