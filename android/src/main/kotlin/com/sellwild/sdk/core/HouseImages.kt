package com.sellwild.sdk.core

import java.net.URL

/** Pure decisions for house and native ad images. */
internal object HouseImages {

    /** Where an image comes from, or why it is refused. */
    sealed class Source {
        /** A `data:` URI: the base64 payload after the first comma. */
        class Inline(val base64: String) : Source()

        /** An http or https URL. */
        class Remote(val url: URL) : Source()

        /**
         * Not loadable. [url] is what logFailure may take a host from: null for a `data:`
         * URI, which has none.
         */
        class Refused(val reason: String, val url: String?) : Source()
    }

    /**
     * `data:` URIs decode inline; anything else must be http or https, so a `file://`
     * value from remote config or listing data cannot turn an image fetch into a
     * local-file read.
     */
    fun source(url: String): Source {
        if (url.startsWith("data:")) {
            val comma = url.indexOf(',')
            if (comma < 0) return Source.Refused("data URI without a comma", url = null)
            return Source.Inline(url.substring(comma + 1))
        }
        val remote = Fetch.httpUrl(url).getOrNull() ?: return Source.Refused("not an http(s) URL", url = url)
        return Source.Remote(remote)
    }

    /** djb2 over the URL's bytes: the stable (launch-independent) disk cache file name. */
    fun djb2(url: String): Long {
        var hash = 5381L
        for (b in url.toByteArray()) hash = hash * 33 + b
        return hash
    }
}
