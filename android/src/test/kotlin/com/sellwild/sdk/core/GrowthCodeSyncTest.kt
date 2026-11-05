package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildEid
import com.sellwild.sdk.SellwildEidUid
import com.sellwild.sdk.factories.EidBlobFactory
import com.sellwild.sdk.factories.GrowthCodeSyncResponseFactory
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pure pieces of the GrowthCode sync. */
class GrowthCodeSyncTest {

    private val hour = 3_600_000L
    private val now = 1_790_000_000_000L

    @Test
    fun `sync without a stored id or last sync, else once the TTL has passed`() {
        assertTrue(GrowthCodeSync.shouldSync(null, now, 48.0, now))
        assertTrue(GrowthCodeSync.shouldSync("gc-1", null, 48.0, now))
        assertFalse(GrowthCodeSync.shouldSync("gc-1", now - 47 * hour, 48.0, now))
        assertTrue(GrowthCodeSync.shouldSync("gc-1", now - 48 * hour, 48.0, now))
        assertTrue(GrowthCodeSync.shouldSync("gc-1", now - hour / 2, 0.5, now))
    }

    @Test
    fun `the request URL adds pid and u, encoded, after any query already there`() {
        assertEquals(
            "https://ids.api.gcprivacy.id/v4/sync/api?pid=pid+1&u=https%3A%2F%2Fweatherbug.com%2F",
            GrowthCodeSync.requestUrl("https://ids.api.gcprivacy.id/v4/sync/api", "pid 1", "https://weatherbug.com/"),
        )
        assertEquals(
            "https://gc.invalid/sync?v=4&pid=p&u=weatherbug.com",
            GrowthCodeSync.requestUrl("https://gc.invalid/sync?v=4", "p", "weatherbug.com"),
        )
    }

    @Test
    fun `the form body leaves out what is missing`() {
        assertEquals("h=weatherbug.com", GrowthCodeSync.formBody(null, "weatherbug.com", null))
        assertEquals("", GrowthCodeSync.formBody("", null, null))
        assertEquals(
            "gcid=gc-1&h=weatherbug.com&maid=38400000-8cf0-11bd-b23e-10b96e40000d&maid_type=GAID",
            GrowthCodeSync.formBody("gc-1", "weatherbug.com", "38400000-8cf0-11bd-b23e-10b96e40000d" to "GAID"),
        )
    }

    @Test
    fun `h is the sync URL's host, or the raw value when it is not a URL`() {
        assertEquals("weatherbug.com", GrowthCodeSync.syncHost("https://weatherbug.com/app"))
        assertEquals("weatherbug.com", GrowthCodeSync.syncHost("weatherbug.com"))
        assertEquals("file:///x", GrowthCodeSync.syncHost("file:///x"))
    }

    @Test
    fun `only a real advertising id is sent`() {
        assertEquals("id-1" to "GAID", GrowthCodeSync.maid("id-1", limitAdTracking = false))
        assertNull(GrowthCodeSync.maid("id-1", limitAdTracking = true))
        assertNull(GrowthCodeSync.maid("00000000-0000-0000-0000-000000000000", limitAdTracking = false))
        assertNull(GrowthCodeSync.maid("", limitAdTracking = false))
        assertNull(GrowthCodeSync.maid(null, limitAdTracking = false))
    }

    @Test
    fun `a response gives gc_id and eb, each absent when missing`() {
        val full = GrowthCodeSync.parseResponse(GrowthCodeSyncResponseFactory.checked().toString())
        val empty = GrowthCodeSync.parseResponse(GrowthCodeSyncResponseFactory.variant("empty").toString())

        assertEquals("gc-fixture-0001", full.gcId)
        assertEquals(GrowthCodeSyncResponseFactory.checked().getString("eb"), full.eb)
        assertEquals(GrowthCodeSync.Response(null, null), empty)
    }

    @Test
    fun `a response that is not JSON throws for the caller to report`() {
        assertThrows(JSONException::class.java) {
            GrowthCodeSync.parseResponse(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"))
        }
    }

    @Test
    fun `the eid blob keeps source and uids, defaults atype to 0 and keeps stype in ext`() {
        val parsed = GrowthCodeSync.parseEidBlob(EidBlobFactory.base().toString())

        assertEquals(
            listOf(
                SellwildEid("uidapi.com", listOf(SellwildEidUid("A4AAAABj-fixture-uid2", 3))),
                SellwildEid(
                    "id5-sync.com",
                    listOf(SellwildEidUid("ID5*fixture", 1), SellwildEidUid("ppid-fixture", 0, mapOf("stype" to "ppuid"))),
                ),
            ),
            parsed.value,
        )
        assertEquals(emptyList<Issue>(), parsed.issues)
    }

    @Test
    fun `an eid blob that is not a JSON array is one parse issue`() {
        val parsed = GrowthCodeSync.parseEidBlob(EidBlobFactory.variant("not-an-array").toString())

        assertEquals(emptyList<SellwildEid>(), parsed.value)
        val issue = parsed.issues.single()
        assertEquals(SellwildFailureCode.GROWTHCODE_EID_PARSE, issue.code)
        assertEquals("growthcode", issue.component)
        assertEquals("warn", issue.severity)
        assertTrue(issue.error is JSONException)
    }

    @Test
    fun `a uid without id alone is dropped with an invalid issue`() {
        val parsed = GrowthCodeSync.parseEidBlob(EidBlobFactory.variant("uid-without-id").toString())

        assertEquals(2, parsed.value.size)
        assertEquals("dropped 0 of 2 entries and 1 uids", parsed.issues.single().message)
    }

    @Test
    fun `an empty eid source or id is dropped, and an empty stype is left out`() {
        val parsed = GrowthCodeSync.parseEidBlob(EidBlobFactory.variant("empty-text-fields").toString())

        assertEquals(
            listOf(SellwildEid("id5-sync.com", listOf(SellwildEidUid("ID5*fixture", 1), SellwildEidUid("ppid-fixture", 0)))),
            parsed.value,
        )
        assertEquals("dropped 2 of 3 entries and 1 uids", parsed.issues.single().message)
    }

    @Test
    fun `an entry without source alone is dropped with an invalid issue`() {
        val parsed = GrowthCodeSync.parseEidBlob(EidBlobFactory.variant("missing-source").toString())

        assertEquals(listOf("id5-sync.com"), parsed.value.map { it.source })
        val issue = parsed.issues.single()
        assertEquals(SellwildFailureCode.GROWTHCODE_EID_INVALID, issue.code)
        assertEquals("dropped 1 of 2 entries and 0 uids", issue.message)
    }

    @Test
    fun `whole entries dropped with no bad uid are one invalid issue`() {
        val parsed = GrowthCodeSync.parseEidBlob(EidBlobFactory.variant("bad-entries-only").toString())

        assertEquals(listOf("uidapi.com", "id5-sync.com"), parsed.value.map { it.source })
        val issue = parsed.issues.single()
        assertEquals(SellwildFailureCode.GROWTHCODE_EID_INVALID, issue.code)
        assertEquals("growthcode", issue.component)
        assertEquals("warn", issue.severity)
        assertEquals("dropped 3 of 5 entries and 0 uids", issue.message)
    }

    @Test
    fun `entries without source or uids, and uids without id, are dropped with one invalid issue`() {
        val blob = EidBlobFactory.variant("partly-invalid")

        val parsed = GrowthCodeSync.parseEidBlob(blob.toString())

        assertEquals(listOf("uidapi.com", "id5-sync.com"), parsed.value.map { it.source })
        assertEquals(2, parsed.value[1].uids.size)
        val issue = parsed.issues.single()
        assertEquals(SellwildFailureCode.GROWTHCODE_EID_INVALID, issue.code)
        assertEquals("dropped 4 of 6 entries and 3 uids", issue.message)
        assertNull(issue.error)
    }
}
