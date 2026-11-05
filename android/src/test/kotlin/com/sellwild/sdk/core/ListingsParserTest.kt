package com.sellwild.sdk.core

import com.sellwild.sdk.SellwildPhoto
import com.sellwild.sdk.SellwildUser
import com.sellwild.sdk.factories.ListingFactory
import com.sellwild.sdk.factories.ListingsResponseFactory
import com.sellwild.sdk.support.FixtureLoader
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** The listings parser on the JVM org.json (ListingsConformanceTest runs it on the device's). */
class ListingsParserTest {

    @Test
    fun `result rs, config and the cache version are read`() {
        val response = ListingsParser.parse(FixtureLoader.text("fixtures/listings-response/valid/rpc-envelope.json"))

        assertEquals(listOf("5550001"), response.listings.map { it.id })
        assertEquals(mapOf<String, Any>("browse" to 1), response.config)
        assertEquals("12", response.widgetCacheVersionId)
    }

    @Test
    fun `rs at the top level, with no config or version, also parses`() {
        val body = ListingsResponseFactory.withItems(ListingFactory.build()).getJSONObject("result").toString()

        val response = ListingsParser.parse(body)

        assertEquals(listOf("105140231"), response.listings.map { it.id })
        assertEquals(emptyMap<String, Any>(), response.config)
        assertNull(response.widgetCacheVersionId)
    }

    @Test
    fun `no rs is no listings`() {
        val body = ListingsResponseFactory.offSchema(mapOf("result" to org.json.JSONObject()))

        assertEquals(0, ListingsParser.parse(body.toString()).listings.size)
    }

    @Test
    fun `every field of a listing is mapped`() {
        val listing = ListingsParser.parseListing(ListingFactory.variant("rpc-item"))

        assertEquals("5550001", listing.id)
        assertEquals("1", listing.status)
        assertEquals("Road bike", listing.title)
        assertEquals("250", listing.price)
        assertEquals("0", listing.shippable)
        assertEquals("7", listing.categoryId)
        assertEquals(
            listOf(SellwildPhoto("https://listings-static1.sellwild.com/x.jpg", "https://listings-static1.sellwild.com/x_thumb.jpg")),
            listing.photos,
        )
        assertEquals(SellwildUser("1234", "Sam", "S", "sam", "5", "1"), listing.user)
        assertNull(listing.text)
        assertNull(listing.url)
        assertNull(listing.currency)
        assertNull(listing.strikePrice)
        assertNull(listing.createdDate)
        assertNull(listing.dataSourceId)
        assertNull(listing.remoteUrl)
        assertFalse(listing.hasPhoto)
    }

    @Test
    fun `every optional field is read`() {
        val listing = ListingsParser.parseListing(ListingFactory.variant("every-field"))

        assertEquals("Low miles, one owner.", listing.text)
        assertEquals("https://sellwild.com/product/105140231", listing.url)
        assertEquals("7", listing.categoryId)
        assertEquals("USD", listing.currency)
        assertEquals("21000", listing.strikePrice)
        assertEquals("2026-09-01T12:00:00Z", listing.createdDate)
        assertEquals(true, listing.hasPhoto)
        assertEquals("#ffffff", listing.photos.single().background)
        assertEquals("https://antengo-listings.s3.us-west-2.amazonaws.com/supply_listings/26/570/231_thumb.jpg", listing.photos.single().thumbUrl)
    }

    @Test
    fun `an absent price and an empty remote_url read as absent`() {
        val listing = ListingsParser.parseListing(ListingFactory.variant("no-price-empty-remote-url"))

        assertNull(listing.price)
        assertNull(listing.remoteUrl)
        assertNull(listing.displayPrice)
    }

    @Test
    fun `numbers are read as text and a listing without user or photos still parses`() {
        val bargain = ListingsParser.parseListing(ListingFactory.variant("bargainhunter"))

        assertEquals("38", bargain.price)
        assertEquals("70", bargain.strikePrice)
        assertNull(bargain.user)
        assertEquals("https://o.bttn.io/19BIp9F5cLj?tag=marketplace-usw-20", bargain.url)

        val noPhotos = ListingsParser.parseListing(ListingFactory.variant("no-photos"))
        assertEquals(emptyList<SellwildPhoto>(), noPhotos.photos)
    }

    @Test
    fun `a body that is not JSON, or an item that is not an object, fails the whole parse`() {
        assertThrows(JSONException::class.java) {
            ListingsParser.parse(FixtureLoader.text("samples/app-config/weatherbug_weatherbug-main.403.xml"))
        }
        val badItem = ListingsResponseFactory.offSchema(
            mapOf("result" to org.json.JSONObject().put("rs", org.json.JSONArray().put("not-a-listing"))),
        )
        assertThrows(JSONException::class.java) { ListingsParser.parse(badItem.toString()) }
    }
}
