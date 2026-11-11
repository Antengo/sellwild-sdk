package com.sellwild.sdk.core

import org.junit.Assert.assertEquals
import org.junit.Test

/** ReaderLink: the reader id on sellwild.com links only, pure. */
class ReaderLinkTest {

    private val id = "3f2b8c1e-7d4a-4b6e-9a1c-5e8f0d2c4b7a"

    @Test
    fun `sellwild_com and www_sellwild_com links get sw_wuid last`() {
        assertEquals(
            "https://sellwild.com/product/1?p=a&sw_wuid=$id",
            ReaderLink.withReaderId("https://sellwild.com/product/1?p=a", id),
        )
        assertEquals(
            "https://www.sellwild.com/product/1?sw_wuid=$id",
            ReaderLink.withReaderId("https://www.sellwild.com/product/1", id),
        )
        assertEquals("https://SellWild.com?sw_wuid=$id", ReaderLink.withReaderId("https://SellWild.com", id))
        assertEquals("https://sellwild.com/?sw_wuid=$id#top", ReaderLink.withReaderId("https://sellwild.com/#top", id))
    }

    @Test
    fun `an old sw_wuid is dropped, other params and the fragment are kept as they were`() {
        assertEquals(
            "https://sellwild.com/p?a=1%202&b&sw_wuidx=y&sw_wuid=$id#f?x=1",
            ReaderLink.withReaderId("https://sellwild.com/p?sw_wuid=old&a=1%202&&b&sw_wuidx=y&sw_wuid#f?x=1", id),
        )
    }

    @Test
    fun `the id is url-encoded`() {
        assertEquals(
            "https://sellwild.com/p?sw_wuid=a%2Fb%26c",
            ReaderLink.withReaderId("https://sellwild.com/p", "a/b&c"),
        )
    }

    @Test
    fun `other hosts, http, relative links and an empty id are unchanged`() {
        listOf(
            "https://o.bttn.io/19BIp9F5cLj?tag=sw-bh",
            "https://autos.lotlinx.com?ad=JTHP3JBH8M2044125&pubId=234000&url=1",
            "https://browse.sellwild.com/x",
            "https://sellwild.com.evil.example/x",
            "https://sellwild.community/x",
            "http://sellwild.com/product/1",
            "/product/1",
            "http://exa mple.invalid/[x",
            "",
        ).forEach { assertEquals(it, ReaderLink.withReaderId(it, id)) }
        assertEquals("https://sellwild.com/product/1", ReaderLink.withReaderId("https://sellwild.com/product/1", ""))
        assertEquals("https://sellwild.com/product/1", ReaderLink.withReaderId("https://sellwild.com/product/1", null))
    }
}
