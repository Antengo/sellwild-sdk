package com.sellwild.sdk.support

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.io.FileNotFoundException

/**
 * [FixtureLoader] reads contract files from the unit-test classpath. The self-test files live
 * in src/test/resources/support-selftest; the real contracts come from ../contracts.
 */
class FixtureLoaderTest {

    @get:Rule
    val network = NetworkBlockRule()

    @Test
    fun `text and jsonObject read a classpath file`() {
        assertTrue(FixtureLoader.text("support-selftest/fixture.json").contains("\"support-selftest\""))

        val json = FixtureLoader.jsonObject("support-selftest/fixture.json")

        assertEquals("support-selftest", json.getString("name"))
        assertEquals(2, json.getInt("count"))
    }

    @Test
    fun `jsonArray reads an array`() {
        val array = FixtureLoader.jsonArray("support-selftest/fixture-array.json")

        assertEquals(2, array.length())
        assertEquals("a", array.getJSONObject(0).getString("id"))
    }

    @Test
    fun `leading slash and surrounding space are ignored`() {
        assertEquals(
            FixtureLoader.text("support-selftest/fixture.json"),
            FixtureLoader.text(" /support-selftest/fixture.json "),
        )
    }

    @Test
    fun `exists reports presence without throwing`() {
        assertTrue(FixtureLoader.exists("support-selftest/fixture.json"))
        assertFalse(FixtureLoader.exists("support-selftest/nope.json"))
    }

    @Test
    fun `missing file names the path and the contracts dir`() {
        val e = assertThrows(FileNotFoundException::class.java) { FixtureLoader.text("fixtures/nope/missing.json") }

        assertTrue(e.message!!.contains("fixtures/nope/missing.json"))
        assertTrue(e.message!!.contains("../contracts"))
    }

    @Test
    fun `paths cannot leave the contracts root`() {
        assertThrows(IllegalArgumentException::class.java) { FixtureLoader.text("../android/build.gradle.kts") }
        assertThrows(IllegalArgumentException::class.java) { FixtureLoader.list("support-selftest/../..") }
        assertThrows(IllegalArgumentException::class.java) { FixtureLoader.text("  ") }
    }

    @Test
    fun `list returns sorted file paths directly inside a dir`() {
        assertEquals(
            listOf("support-selftest/listing/a.json", "support-selftest/listing/b.json"),
            FixtureLoader.list("support-selftest/listing/"),
        )
        // The listing/ and schemas/ subdirectories are left out.
        assertEquals(
            listOf("support-selftest/fixture-array.json", "support-selftest/fixture.json"),
            FixtureLoader.list("support-selftest"),
        )
    }

    @Test
    fun `list of an absent dir is empty`() {
        assertEquals(emptyList<String>(), FixtureLoader.list("support-selftest/absent"))
    }

    @Test
    fun `the contracts schemas dir is mirrored on the classpath`() {
        // Gradle runs unit tests from the module dir, so ../contracts is sellwild-sdk/contracts.
        val onDisk = File(System.getProperty("user.dir"), "../contracts/schemas")
            .listFiles()?.filter { it.isFile }?.map { "schemas/${it.name}" }?.sorted().orEmpty()

        assertEquals(onDisk, FixtureLoader.list("schemas"))
    }
}
