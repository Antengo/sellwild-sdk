package com.sellwild.sdk.support

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.ProtocolException
import java.net.URL
import java.net.URLConnection
import java.util.concurrent.CopyOnWriteArrayList
import java.util.function.Function

/**
 * Answers http/https requests inside the test JVM, so SDK code that opens its own
 * HttpURLConnection (the events queue, the config and listings fetches) runs end to end with
 * no network. Nothing leaves the process: [NetworkBlock]'s handler asks the stub first, and a
 * URL the stub declines (`null`) is blocked and recorded as usual.
 *
 * ```
 * val requests = HttpStub.install { StubResponse(200) }.use { stub ->
 *     runBlocking { queue.flush() }
 *     stub.requests
 * }
 * ```
 *
 * One stub at a time, JVM-wide: the SDK sends from its own IO threads, and Robolectric's
 * sandbox class loader reaches the same stub. [NetworkBlockAuditListener] removes and reports a
 * stub a test forgot to close.
 */
class HttpStub private constructor(private val respond: (URL) -> StubResponse?) : AutoCloseable {
    private val sent = CopyOnWriteArrayList<CapturedRequest>()
    private val drainedUrls = CopyOnWriteArrayList<URL>()
    private val opener = Function<URL, URLConnection?> { url ->
        respond(url)?.let { StubConnection(url, it, sent::add, drainedUrls::add) }
    }

    /** Requests sent so far, oldest first. A request is sent once it connects or its response is read. */
    val requests: List<CapturedRequest> get() = sent.toList()

    /**
     * URLs whose response body (the input or the error stream) was read to the end and then
     * closed, oldest first: what returns an HttpURLConnection socket to the keep-alive pool.
     */
    val drained: List<URL> get() = drainedUrls.toList()

    /** Uninstalls the stub; later requests are blocked again. */
    override fun close() {
        NetworkBlock.clearStub(opener)
    }

    companion object {
        /** Installs a stub that answers each URL with [respond]'s response, or blocks it on null. */
        fun install(respond: (URL) -> StubResponse?): HttpStub =
            HttpStub(respond).also { NetworkBlock.setStub(it.opener) }
    }
}

/** What an [HttpStub] answers. Header names match case-insensitively, as in HttpURLConnection. */
data class StubResponse(
    val status: Int = 200,
    val body: String = "",
    val headers: Map<String, String> = emptyMap(),
)

/** One request an [HttpStub] answered. [headers] are the request properties the code set. */
class CapturedRequest(
    val url: URL,
    val method: String,
    val headers: Map<String, String>,
    val body: ByteArray,
) {
    fun bodyText(): String = body.toString(Charsets.UTF_8)
}

/**
 * An in-memory HttpURLConnection that follows the JDK where the SDK depends on it: writing
 * needs doOutput, a GET with a body becomes a POST, the request is sent on connect or the first
 * response read, request properties are frozen after that, and an error status makes
 * [getInputStream] throw (FileNotFoundException for 404 and 410) while [getErrorStream] holds
 * the body.
 */
private class StubConnection(
    url: URL,
    private val response: StubResponse,
    private val onSend: (CapturedRequest) -> Unit,
    private val onDrained: (URL) -> Unit,
) : HttpURLConnection(url) {
    private val output = ByteArrayOutputStream()
    private val body = response.body.toByteArray(Charsets.UTF_8)

    override fun connect() {
        if (connected) return
        val headers = requestProperties.mapValues { (_, values) -> values.joinToString(",") }
        connected = true
        onSend(CapturedRequest(url, method, headers, output.toByteArray()))
    }

    override fun disconnect() = Unit

    override fun usingProxy(): Boolean = false

    override fun getOutputStream(): OutputStream {
        if (!doOutput) {
            throw ProtocolException("cannot write to a URLConnection if doOutput=false - call setDoOutput(true)")
        }
        if (connected) throw ProtocolException("Cannot write output after reading input.")
        if (method == "GET") method = "POST"
        return output
    }

    override fun getResponseCode(): Int {
        connect()
        return response.status
    }

    override fun getInputStream(): InputStream {
        connect()
        if (response.status >= 400) {
            if (response.status == 404 || response.status == 410) throw FileNotFoundException(url.toString())
            throw IOException("Server returned HTTP response code: ${response.status} for URL: $url")
        }
        return DrainTracking(body) { onDrained(url) }
    }

    override fun getErrorStream(): InputStream? =
        if (connected && response.status >= 400) DrainTracking(body) { onDrained(url) } else null

    override fun getHeaderField(name: String?): String? {
        connect()
        return response.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
    }

    override fun getHeaderFields(): Map<String?, List<String>> {
        connect()
        return response.headers.mapValues { listOf(it.value) }
    }
}

/** A response body that reports, on close, whether it was read to the end. */
private class DrainTracking(body: ByteArray, private val onDrained: () -> Unit) : ByteArrayInputStream(body) {
    override fun close() {
        if (available() == 0) onDrained()
        super.close()
    }
}
