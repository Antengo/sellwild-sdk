package com.sellwild.sdk.support

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.FileNotFoundException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.ProtocolException
import java.net.URL

/**
 * [HttpStub] answers requests in-process through [NetworkBlock]'s handler, captures what the
 * code sent, and behaves like the JDK connection where SDK code depends on it.
 */
class HttpStubTest {

    @get:Rule
    val network = NetworkBlockRule()

    @Test
    fun `a stubbed POST is captured and answered`() {
        val stub = HttpStub.install { StubResponse(201, """{"ok":true}""", mapOf("Content-Type" to "application/json")) }
        stub.use {
            val conn = URL("https://stub.invalid/events/queue").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.outputStream.use { it.write("""[{"event":"x"}]""".toByteArray()) }

            assertEquals(201, conn.responseCode)
            assertEquals("""{"ok":true}""", conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) })
            assertEquals("application/json", conn.getHeaderField("content-type"))
            assertNull(conn.errorStream)
        }

        val request = stub.requests.single()
        assertEquals(URL("https://stub.invalid/events/queue"), request.url)
        assertEquals("POST", request.method)
        assertEquals(mapOf("Content-Type" to "application/json"), request.headers)
        assertEquals("""[{"event":"x"}]""", request.bodyText())
        assertTrue(network.attempts.isEmpty())
    }

    @Test
    fun `a GET is sent when its response is read`() {
        HttpStub.install { StubResponse(body = "cfg") }.use { stub ->
            val conn = URL("https://stub.invalid/app.json").openConnection() as HttpURLConnection
            conn.setRequestProperty("User-Agent", "SellwildSDK/test (android)")

            assertTrue(stub.requests.isEmpty())
            assertEquals("cfg", conn.inputStream.bufferedReader().readText())

            val request = stub.requests.single()
            assertEquals("GET", request.method)
            assertEquals("SellwildSDK/test (android)", request.headers["User-Agent"])
            assertArrayEquals(ByteArray(0), request.body)
            // Sent once, however often the response is read.
            assertEquals(200, conn.responseCode)
            assertEquals(1, stub.requests.size)
        }
    }

    @Test
    fun `writing follows the JDK rules`() {
        HttpStub.install { StubResponse() }.use {
            val noOutput = URL("https://stub.invalid/a").openConnection() as HttpURLConnection
            assertThrows(ProtocolException::class.java) { noOutput.outputStream }

            val get = URL("https://stub.invalid/b").openConnection() as HttpURLConnection
            get.doOutput = true
            get.outputStream.write(1)
            assertEquals("POST", get.requestMethod)
            assertEquals(200, get.responseCode)
            assertThrows(ProtocolException::class.java) { get.outputStream }
            assertThrows(IllegalStateException::class.java) { get.setRequestProperty("X-Late", "1") }
        }
    }

    @Test
    fun `error statuses throw from inputStream and fill errorStream`() {
        HttpStub.install { url -> StubResponse(if (url.path == "/missing") 404 else 503, "down") }.use {
            val missing = URL("https://stub.invalid/missing").openConnection() as HttpURLConnection
            assertThrows(FileNotFoundException::class.java) { missing.inputStream }
            assertEquals(404, missing.responseCode)

            val down = URL("https://stub.invalid/down").openConnection() as HttpURLConnection
            val e = assertThrows(IOException::class.java) { down.inputStream }
            assertEquals("Server returned HTTP response code: 503 for URL: https://stub.invalid/down", e.message)
            assertEquals("down", down.errorStream!!.bufferedReader().readText())
        }
    }

    @Test
    fun `a declined URL is still blocked`() {
        network.expectAttempts()

        HttpStub.install { url -> if (url.host == "stub.invalid") StubResponse() else null }.use { stub ->
            assertThrows(NetworkBlockedException::class.java) { URL("https://other.invalid/x").openConnection() }
            assertTrue(stub.requests.isEmpty())
        }

        assertEquals(listOf("https://other.invalid/x"), network.attempts)
    }

    @Test
    fun `close restores the block and frees the slot`() {
        network.expectAttempts()
        val first = HttpStub.install { StubResponse() }

        val second = assertThrows(IllegalStateException::class.java) { HttpStub.install { StubResponse() } }
        assertTrue(second.message!!.contains("Another HttpStub is still installed"))
        first.close()

        assertThrows(NetworkBlockedException::class.java) { URL("https://stub.invalid/after").openConnection() }
        HttpStub.install { StubResponse(204) }.use {
            assertEquals(204, (URL("https://stub.invalid/again").openConnection() as HttpURLConnection).responseCode)
        }
    }
}
