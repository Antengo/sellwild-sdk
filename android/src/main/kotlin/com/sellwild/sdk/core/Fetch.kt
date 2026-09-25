package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildGeo
import com.sellwild.sdk.failures.SellwildFailureCode
import org.json.JSONException
import java.io.IOException
import java.net.MalformedURLException
import java.net.SocketTimeoutException
import java.net.URL

/** The registry codes one kind of fetch reports when it throws (FAILURES.md 4.1 reasons). */
internal class FetchCodes(val network: String, val timeout: String, val parse: String, val exception: String)

/** Pure decisions shared by the SDK's HTTP fetches. */
internal object Fetch {

    val LISTINGS = FetchCodes(
        network = SellwildFailureCode.LISTINGS_FETCH_NETWORK,
        timeout = SellwildFailureCode.LISTINGS_FETCH_TIMEOUT,
        parse = SellwildFailureCode.LISTINGS_FETCH_PARSE,
        exception = SellwildFailureCode.LISTINGS_FETCH_EXCEPTION,
    )

    val LOCALIZED = FetchCodes(
        network = SellwildFailureCode.LOCALIZED_FETCH_NETWORK,
        timeout = SellwildFailureCode.LOCALIZED_FETCH_TIMEOUT,
        parse = SellwildFailureCode.LOCALIZED_FETCH_PARSE,
        exception = SellwildFailureCode.LOCALIZED_FETCH_EXCEPTION,
    )

    /** The remote config fetch. What throws past the network is applying the config. */
    val CONFIG = FetchCodes(
        network = SellwildFailureCode.CONFIG_FETCH_NETWORK,
        timeout = SellwildFailureCode.CONFIG_FETCH_TIMEOUT,
        parse = SellwildFailureCode.CONFIG_FETCH_PARSE,
        exception = SellwildFailureCode.CONFIG_APPLY_EXCEPTION,
    )

    val GROWTHCODE = FetchCodes(
        network = SellwildFailureCode.GROWTHCODE_SYNC_NETWORK,
        timeout = SellwildFailureCode.GROWTHCODE_SYNC_TIMEOUT,
        parse = SellwildFailureCode.GROWTHCODE_SYNC_PARSE,
        exception = SellwildFailureCode.GROWTHCODE_SYNC_EXCEPTION,
    )

    /**
     * The code for a fetch that threw [e]: a socket timeout is `timeout`, a body that is not
     * JSON is `parse`, an IOException (DNS, offline, TLS, reset, a stream that broke) or a
     * SecurityException (no INTERNET permission) is `network`, and anything else (a stored
     * value of the wrong type, an SDK call that refused) is `exception`.
     */
    fun codeFor(e: Throwable, codes: FetchCodes): String = when (e) {
        is SocketTimeoutException -> codes.timeout
        is JSONException -> codes.parse
        is IOException, is SecurityException -> codes.network
        else -> codes.exception
    }

    /**
     * [text] as an http or https URL. A failure holds the MalformedURLException that says
     * why not: the text is not a URL, or its scheme is another one (file:, ftp:, ...).
     */
    fun httpUrl(text: String): Result<URL> = try {
        val url = URL(text)
        if (url.protocol == "http" || url.protocol == "https") {
            Result.success(url)
        } else {
            Result.failure(MalformedURLException("not an http(s) URL: ${url.protocol}"))
        }
    } catch (e: MalformedURLException) {
        Result.failure(e)
    }

    /**
     * A 403 or 404 from a per-state localized cache means that state has no cache (S3
     * answers 403 for a missing key). It is a normal skip, not a failure.
     */
    fun isMissingStateCache(status: Int): Boolean = status == 403 || status == 404

    /**
     * The geo to store after a listings response carried CloudFront's viewer headers, or
     * null when nothing changes. Only an empty state or country is filled: a partner-set or
     * earlier value is never overwritten. The country is kept only when it maps to a North
     * America alpha-3 code (OpenRTB wants alpha-3).
     */
    fun seededGeo(current: SellwildGeo?, region: String?, countryAlpha2: String?): SellwildGeo? {
        var geo = current ?: SellwildGeo()
        var changed = false
        val r = trimmedOrNull(region)
        if (geo.state.isNullOrEmpty() && r != null) {
            geo = geo.copy(state = r)
            changed = true
        }
        val alpha3 = trimmedOrNull(countryAlpha2)?.let { SellwildGeo.northAmericaAlpha3(it) }
        if (geo.country.isNullOrEmpty() && alpha3 != null) {
            geo = geo.copy(country = alpha3)
            changed = true
        }
        return if (changed) geo else null
    }

    private fun trimmedOrNull(s: String?): String? {
        if (s == null) return null
        val trimmed = s.trim()
        return if (trimmed.isEmpty()) null else trimmed
    }
}
