package com.sellwild.sdk.support

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * [ContractEmitter] writes `<schema>.<variant>.json` for contracts/scripts/validate.mjs. These
 * tests write to a temp dir so they never leave files in contracts/out/android.
 */
class ContractEmitterTest {

    @get:Rule
    val network = NetworkBlockRule()

    @get:Rule
    val tmp = TemporaryFolder()

    @Test
    fun `emit writes schema dot variant json that parses back`() {
        val dir = tmp.newFolder("out")
        val json = JSONObject().put("CODE", "weatherbug").put("BIDDERS", JSONArray().put("appnexus"))

        val file = ContractEmitter.emit("app-config", "minimal", json, dir)

        assertEquals(File(dir, "app-config.minimal.json"), file)
        val back = JSONObject(file.readText())
        assertEquals("weatherbug", back.getString("CODE"))
        assertEquals("appnexus", back.getJSONArray("BIDDERS").getString(0))
    }

    @Test
    fun `emit accepts arrays and creates missing dirs`() {
        val dir = File(tmp.root, "nested/android")

        val file = ContractEmitter.emit("events-batch", "client_failure", JSONArray().put(JSONObject().put("event", "x")), dir)

        assertTrue(file.isFile)
        assertEquals("x", JSONArray(file.readText()).getJSONObject(0).getString("event"))
    }

    @Test
    fun `emitText keeps the exact serialized body`() {
        val dir = tmp.newFolder("text")
        val body = """[{"event":"clientFailure","uid":"u1","createdTime":1790000000000}]"""

        val file = ContractEmitter.emitText("events-batch", "wire-body", body, dir)

        assertEquals("$body\n", file.readText())
    }

    @Test
    fun `emitText rejects text that is not a JSON object or array`() {
        val dir = tmp.newFolder("bad")

        assertThrows(IllegalArgumentException::class.java) { ContractEmitter.emitText("app-config", "scalar", "42", dir) }
        assertThrows(RuntimeException::class.java) { ContractEmitter.emitText("app-config", "broken", "{\"a\":", dir) }
        assertFalse(File(dir, "app-config.scalar.json").exists())
    }

    @Test
    fun `names that would confuse validate mjs are rejected`() {
        val dir = tmp.newFolder("names")
        val json = JSONObject()

        for (schema in listOf("", "App-Config", "app.config", "../app-config", "app_config")) {
            assertThrows(schema, IllegalArgumentException::class.java) { ContractEmitter.emit(schema, "ok", json, dir) }
        }
        for (variant in listOf("", "with.dot", "a/b", "-lead")) {
            assertThrows(variant, IllegalArgumentException::class.java) { ContractEmitter.emit("app-config", variant, json, dir) }
        }
        assertEquals(0, dir.listFiles()!!.size)
    }

    @Test
    fun `Gradle passes the out dir the fallback computes`() {
        val configured = System.getProperty(ContractEmitter.OUT_DIR_PROPERTY)
        val moduleDir = System.getProperty("user.dir")!!

        assertNotNull("android/build.gradle.kts passes ${ContractEmitter.OUT_DIR_PROPERTY}", configured)
        assertEquals(File(configured!!), ContractEmitter.outDir())
        assertEquals(ContractEmitter.defaultOutDir(System.getenv(ContractEmitter.OUT_ROOT_ENV), moduleDir), ContractEmitter.outDir())
    }

    @Test
    fun `out dir falls back to the computed default`() {
        val saved = System.getProperty(ContractEmitter.OUT_DIR_PROPERTY)
        System.clearProperty(ContractEmitter.OUT_DIR_PROPERTY)
        try {
            val expected = ContractEmitter.defaultOutDir(System.getenv(ContractEmitter.OUT_ROOT_ENV), System.getProperty("user.dir")!!)
            assertEquals(expected, ContractEmitter.outDir())
        } finally {
            saved?.let { System.setProperty(ContractEmitter.OUT_DIR_PROPERTY, it) }
        }
    }

    @Test
    fun `default out dir follows SELLWILD_CONTRACT_OUT like validate mjs`() {
        val module = "/r/sellwild-sdk/android"

        assertEquals(File("/r/sellwild-sdk/contracts/out/android"), ContractEmitter.defaultOutDir(null, module))
        assertEquals(File("/r/sellwild-sdk/contracts/out/android"), ContractEmitter.defaultOutDir(" ", module))
        assertEquals(File("/x/contract-out/android"), ContractEmitter.defaultOutDir("/x/contract-out", module))
        assertEquals(File("/r/sellwild-sdk/android/rel/out/android"), ContractEmitter.defaultOutDir("rel/out", module))
    }
}
