package com.sellwild.sdk

import org.json.JSONArray
import org.json.JSONObject

/**
 * Tolerant reader for the CDN `S2S_CONFIG` key (the Prebid.js `s2sConfig`).
 *
 * The CMS ships it as a JS object-literal STRING, e.g.
 * `"[{ accountId: 'weatherbug', endpoint: { p1Consent: 'https://…' }, timeout: 1300, }]"`
 * — unquoted keys, single quotes, maybe trailing commas — so
 * `optJSONObject("S2S_CONFIG")` was always null. This accepts an already-parsed
 * [JSONObject] / [JSONArray], a real JSON string, or that JS-literal form, and
 * extracts the first entry's account id, auction endpoint and timeout.
 */
internal data class SellwildS2SConfig(
    val accountId: String?,
    /**
     * Prebid Server auction URL. Prebid.js allows `endpoint` to be a string or
     * `{ p1Consent, noP1Consent }`; the consented URL wins.
     */
    val endpoint: String?,
    /** S2S auction timeout in ms. */
    val timeout: Int?,
) {
    companion object {
        /**
         * Parse the raw `S2S_CONFIG` value. Returns null when it is absent, not
         * parseable, or carries none of the fields we read.
         */
        fun parse(raw: Any?): SellwildS2SConfig? {
            val value: Any? = if (raw is String) {
                // Always normalize first: valid JSON passes through unchanged, and
                // it keeps results independent of org.json's (platform-specific)
                // leniency toward unquoted keys / single quotes.
                val json = jsLiteralToJson(raw).trim()
                runCatching {
                    when {
                        json.startsWith("{") -> JSONObject(json)
                        json.startsWith("[") -> JSONArray(json)
                        else -> null
                    }
                }.getOrNull()
            } else raw
            val entry = when (value) {
                is JSONObject -> value
                is JSONArray -> value.optJSONObject(0)
                else -> null
            } ?: return null

            val result = SellwildS2SConfig(
                accountId = nonEmpty(entry.opt("accountId")) ?: nonEmpty(entry.opt("account")),
                endpoint = endpointUrl(entry.opt("endpoint")) ?: nonEmpty(entry.opt("url")),
                timeout = positiveInt(entry.opt("timeout")),
            )
            if (result.accountId == null && result.endpoint == null && result.timeout == null) return null
            return result
        }

        private fun nonEmpty(v: Any?): String? = (v as? String)?.takeIf { it.isNotEmpty() }

        private fun endpointUrl(v: Any?): String? =
            if (v is JSONObject) nonEmpty(v.opt("p1Consent")) ?: nonEmpty(v.opt("noP1Consent"))
            else nonEmpty(v)

        private fun positiveInt(v: Any?): Int? {
            val n = when (v) {
                is Number -> v.toInt()
                is String -> v.toIntOrNull()
                else -> null
            }
            return n?.takeIf { it > 0 }
        }

        /**
         * Rewrite a JS object/array literal into JSON: quote bare keys, turn
         * single-quoted strings into double-quoted ones (re-escaping as needed),
         * map `undefined` → `null`, and drop trailing commas and comments. Valid
         * JSON passes through unchanged. Not a full JS parser — just enough for
         * CMS-authored config literals; anything else fails the JSON parse after.
         */
        internal fun jsLiteralToJson(s: String): String {
            val out = StringBuilder(s.length + 16)
            var i = 0
            fun isIdentStart(ch: Char) = ch == '_' || ch == '$' || ch.isLetter()
            fun isIdentPart(ch: Char) = isIdentStart(ch) || ch.isDigit()
            fun nextSignificant(from: Int): Int {
                var k = from
                while (k < s.length && s[k].isWhitespace()) k++
                return k
            }
            while (i < s.length) {
                val ch = s[i]
                when {
                    ch == '"' || ch == '\'' -> {
                        // String literal → double-quoted JSON string.
                        out.append('"')
                        i++
                        while (i < s.length && s[i] != ch) {
                            val x = s[i]
                            if (x == '\\' && i + 1 < s.length) {
                                // `\'` isn't a JSON escape; everything else carries over.
                                if (s[i + 1] == '\'') out.append('\'') else out.append(x).append(s[i + 1])
                                i += 2
                                continue
                            }
                            when (x) {
                                '"' -> out.append("\\\"")
                                '\n' -> out.append("\\n")
                                '\r' -> out.append("\\r")
                                '\t' -> out.append("\\t")
                                else -> out.append(x)
                            }
                            i++
                        }
                        out.append('"')
                        i++
                    }
                    ch == '/' && i + 1 < s.length && s[i + 1] == '/' -> {
                        while (i < s.length && s[i] != '\n') i++
                    }
                    ch == '/' && i + 1 < s.length && s[i + 1] == '*' -> {
                        i += 2
                        while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) i++
                        i += 2
                    }
                    ch == ',' -> {
                        val k = nextSignificant(i + 1)
                        // Drop trailing commas before a closing bracket.
                        if (!(k < s.length && (s[k] == '}' || s[k] == ']'))) out.append(ch)
                        i++
                    }
                    ch.isDigit() -> {
                        // Number: copy through (keeps `1e3` from being read as a key).
                        while (i < s.length && (isIdentPart(s[i]) || s[i] == '.' ||
                                ((s[i] == '+' || s[i] == '-') && (s[i - 1] == 'e' || s[i - 1] == 'E')))
                        ) {
                            out.append(s[i])
                            i++
                        }
                    }
                    isIdentStart(ch) -> {
                        var j = i
                        while (j < s.length && isIdentPart(s[j])) j++
                        val word = s.substring(i, j)
                        val k = nextSignificant(j)
                        when {
                            k < s.length && s[k] == ':' -> out.append('"').append(word).append('"')
                            word == "undefined" -> out.append("null")
                            else -> out.append(word) // true / false / null
                        }
                        i = j
                    }
                    else -> {
                        out.append(ch)
                        i++
                    }
                }
            }
            return out.toString()
        }
    }
}
