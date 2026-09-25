// JVM checks for the Android React Native bridge (react-native/android), run
// by native-checks/run.sh. They run the bridge code itself on the JVM: the
// pure rules, the config readers, the per-view props logic, the event emitter
// and the SellwildRNModule methods. Stand-ins replace React Native and the
// Prebid fork (android/api-stubs, android/runtime-stubs); FakeMap and
// FakeArray behave like React Native's ReadableNativeMap and Array.
//
// Every failure site is checked for its code, its text and how many times
// logFailure ran for it (calls, counted before the 60 s dedupe, so a second
// identical call cannot hide behind it).
package com.sellwild.rnsdk

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.sellwild.prebid.ExternalUserId
import com.sellwild.prebid.TargetingParams
import com.sellwild.sdk.AdSize
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildGeoStore
import com.sellwild.sdk.failures.FailureEvent
import com.sellwild.sdk.failures.FailureSink
import com.sellwild.sdk.failures.SellwildFailures

private var checks = 0
private var failed = 0

private fun check(ok: Boolean, name: String) {
    checks++
    if (!ok) {
        failed++
        System.err.println("FAIL: $name")
    }
}

private class Sink : FailureSink {
    override val uid = "8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11"
    val events = ArrayList<FailureEvent>()
    override fun push(event: FailureEvent, flushNow: Boolean) {
        events += event
    }
}

/** What logFailure did while a block ran. */
private class Logged(val events: List<FailureEvent>, val calls: Map<String, Int>) {
    /** Each event as (code, msg). */
    val sent: List<Pair<String, String?>> get() = events.map { it.action to it.attributes["msg"] }
    fun attr(name: String): String? = events.single().attributes[name]
    override fun toString() = "events=${events.map { it.attributes }} calls=$calls"
}

/** Runs [block] with logFailure reset and bound to a fake sink. */
private fun logged(block: () -> Unit): Logged {
    SellwildFailures.resetForTests()
    SellwildFailures.setWrapper("react-native")
    val sink = Sink()
    SellwildFailures.bind(sink)
    block()
    // logFailure calls per code, the ones the dedupe suppressed included.
    val calls = SellwildFailures.gateState.keys
        .groupBy { it.key.substringBefore('|') }
        .mapValues { (_, keys) -> keys.sumOf { it.emits + it.suppressed } }
    return Logged(sink.events.toList(), calls)
}

// The runtime stand-ins' hooks. The checks compile against the React Native
// API stubs, so the runtime-only members are reached by reflection.
private fun setJsModule(module: Any?) {
    Class.forName("com.facebook.react.bridge.ReactContext").getField("jsModule").set(null, module)
}

@Suppress("UNCHECKED_CAST")
private fun uiQueue(): MutableList<Runnable> =
    Class.forName("com.facebook.react.bridge.UiThreadUtil").getField("queued").get(null) as MutableList<Runnable>

private fun context(): ReactApplicationContext =
    Class.forName("com.facebook.react.bridge.ReactApplicationContext").getDeclaredConstructor().newInstance() as ReactApplicationContext

private fun module(): SellwildModule = SellwildModule(context())

fun main() {
    rules()
    setGeo()
    setExternalUserIds()
    prewarm()
    emit()
    bannerProps()
    feedProps()
    configReaders()
    println("$checks checks, $failed failed")
    kotlin.system.exitProcess(if (failed == 0) 0 else 1)
}

private fun rules() {
    val supports = { s: String -> SellwildBannerViewManager.adSizeFromLabel(s) != null }
    // bannerPropsProblem, with the real Android label table.
    check(RnBridgeRules.bannerPropsProblem(true, "300x250", "43", supports) == null, "props ok")
    check(RnBridgeRules.bannerPropsProblem(false, "300x250", "43", supports) == "the config prop is missing", "no config")
    check(RnBridgeRules.bannerPropsProblem(true, "300x250", null, supports) == "the zoneId prop is missing", "no zone")
    check(RnBridgeRules.bannerPropsProblem(true, "1x1", "43", supports) == "size 1x1 has no native ad size", "1x1")
    check(RnBridgeRules.bannerPropsProblem(true, "999x1", "43", supports) == null, "JS reported label")
    check(RnBridgeRules.bannerPropsProblem(true, null, "43", supports) == null, "JS reported missing size")
    for (label in RnBridgeRules.JS_AD_SIZE_LABELS - "1x1") check(supports(label), "native has $label")
    check(RnBridgeRules.prebidServerProblem(true, true) == null, "pbs ok")
    check(RnBridgeRules.prebidServerProblem(false, false) == "prebidServer has no accountId or endpoint text, so the default Prebid Server is used", "pbs none")
    check(RnBridgeRules.prebidServerNotObject("String") == "prebidServer is text, not an object, so the default Prebid Server is used", "pbs not object")
    check(RnBridgeRules.eidsProblem(0, 3, 0) == null, "eids ok")
    check(RnBridgeRules.eidsProblem(1, 3, 2) == "skipped 1 of 3 eids without source or a uids list, and 2 uids without id", "eids text")
    check(RnBridgeRules.eidsProblem(0, 1, 1) == "skipped 0 of 1 eids without source or a uids list, and 1 uids without id", "eids only uids skipped")
    check(RnBridgeRules.eidsProblem(2, 2, 0) == "skipped 2 of 2 eids without source or a uids list, and 0 uids without id", "eids only entries skipped")
    check(RnBridgeRules.geoNotObject("Null") == "geo is null, not an object, so geo was cleared", "geo not object")
    check(RnBridgeRules.kind("Number") == "a number" && RnBridgeRules.kind("Other") == "Other", "kind")
    val kinds = listOf("Null", "Boolean", "Number", "String", "Map", "Array").map(RnBridgeRules::kind)
    check(kinds == listOf("null", "a boolean", "a number", "text", "an object", "a list"), "kind names: $kinds")

    // geoWrongTyped: absent, null and the right type are fine; anything else is named, in field order.
    val types = mapOf("state" to "String", "zip" to "Number", "lat" to "String", "lon" to "Null", "type" to "Boolean", "city" to "Map")
    val wrong = RnBridgeRules.geoWrongTyped { types[it] }
    check(wrong.keys.toList() == listOf("city", "zip", "lat", "type"), "geo wrong keys: ${wrong.keys}")
    check(
        wrong.values.toList() == listOf(
            "geo.city is an object, not text, so it was dropped",
            "geo.zip is a number, not text, so it was dropped",
            "geo.lat is text, not a number, so it was dropped",
            "geo.type is a boolean, not a number, so it was dropped",
        ),
        "geo wrong text: ${wrong.values}",
    )
    check(RnBridgeRules.geoWrongTyped { null }.isEmpty(), "geo nothing sent")
    check(RnBridgeRules.GEO_FIELD_TYPES.keys.toList() == listOf("country", "state", "city", "zip", "metro", "lat", "lon", "type"), "geo fields")
    // Each field on its own, sent with a type it cannot have.
    for ((key, want) in RnBridgeRules.GEO_FIELD_TYPES) {
        val sent = if (want == "String") "Number" else "String"
        val one = RnBridgeRules.geoWrongTyped { if (it == key) sent else null }
        val text = if (want == "String") "geo.$key is a number, not text, so it was dropped" else "geo.$key is text, not a number, so it was dropped"
        check(one == mapOf(key to text), "geo $key wrong: $one")
    }

    // ReportOnce: a problem is reported when it is not the last one reported.
    val once = ReportOnce()
    check(once.take(null) == null, "once: nothing")
    check(once.take("a") == "a", "once: first a")
    check(once.take("a") == null, "once: a again")
    check(once.take("b") == "b", "once: b")
    check(once.take("b") == null, "once: b again")
    check(once.take(null) == null, "once: fine again")
    check(once.take("b") == "b", "once: b after fine")
}

private fun setGeo() {
    val m = module()
    // lat sent as text. At HEAD this threw from getDouble and crashed the host app.
    val latText = logged { m.setGeo(FakeMap(mapOf("state" to "NY", "zip" to "10001", "lat" to "40.7", "lon" to -74.0))) }
    check(latText.sent == listOf("bridge.geo.invalid" to "geo.lat is text, not a number, so it was dropped"), "setGeo lat text: $latText")
    check(latText.calls == mapOf("bridge.geo.invalid" to 1) && latText.attr("severity") == "warn", "setGeo lat text once: $latText")
    val kept = SellwildGeoStore.current
    check(kept?.state == "NY" && kept.zip == "10001" && kept.lat == null && kept.lon == -74.0, "setGeo keeps the other fields: $kept")
    val ortb = TargetingParams.lastGlobalOrtb
    check(ortb?.contains("\"region\":\"NY\"") == true && !ortb.contains("\"lat\""), "Prebid got the geo without lat: $ortb")

    // Every field typed: set, no report.
    val good = logged { m.setGeo(FakeMap(mapOf("state" to "CA", "lat" to 37.7, "lon" to -122.4, "type" to 2.0, "country" to null))) }
    check(good.calls.isEmpty() && SellwildGeoStore.current?.lat == 37.7 && SellwildGeoStore.current?.type == 2, "setGeo typed: $good ${SellwildGeoStore.current}")

    // {} (what JS sends to clear) clears, with no report.
    check(logged { m.setGeo(FakeMap(emptyMap())) }.calls.isEmpty() && SellwildGeoStore.current == null, "setGeo {} clears")

    // null (only from outside the JS API) clears too, and is reported, as on iOS.
    m.setGeo(FakeMap(mapOf("state" to "CA")))
    val nothing = logged { m.setGeo(null) }
    check(nothing.sent == listOf("bridge.geo.invalid" to "geo is null, not an object, so geo was cleared"), "setGeo null: $nothing")
    check(nothing.calls == mapOf("bridge.geo.invalid" to 1) && SellwildGeoStore.current == null, "setGeo null clears once: $nothing")

    // Only wrong-typed fields: reported once, and geo is cleared (nothing usable).
    m.setGeo(FakeMap(mapOf("state" to "CA")))
    val allWrong = logged { m.setGeo(FakeMap(mapOf("lat" to true, "state" to 5.0))) }
    check(
        allWrong.sent == listOf("bridge.geo.invalid" to "geo.state is a number, not text, so it was dropped; geo.lat is a boolean, not a number, so it was dropped"),
        "setGeo all wrong: $allWrong",
    )
    check(allWrong.calls == mapOf("bridge.geo.invalid" to 1) && SellwildGeoStore.current == null, "setGeo all wrong clears: $allWrong")

    // A map that cannot be read at all: reported once with the error, geo cleared.
    m.setGeo(FakeMap(mapOf("state" to "CA")))
    val broken = logged { m.setGeo(BrokenMap()) }
    // The msg is the message, then the error's own text (FAILURES.md 7.5).
    check(broken.sent == listOf("bridge.geo.invalid" to "geo could not be read, so geo was cleared: the bridged map is gone"), "setGeo broken: $broken")
    check(broken.calls == mapOf("bridge.geo.invalid" to 1) && broken.attr("errName") == "IllegalStateException", "setGeo broken once: $broken")
    check(SellwildGeoStore.current == null, "setGeo broken clears")
}

/** The eids the last setExternalUserIds handed Prebid, as (source, [(id, atype, ext)]). */
private fun prebidEids(): List<Pair<String, List<Triple<String, Int?, Map<String, Any>?>>>>? =
    TargetingParams.lastExternalUserIds?.map { eid: ExternalUserId ->
        eid.source to eid.uniqueIds.map { Triple(it.id, it.atype, it.ext) }
    }

private fun setExternalUserIds() {
    val m = module()
    val id5 = mapOf("source" to "id5-sync.com", "uids" to listOf(mapOf("id" to "ID5-1", "atype" to 1.0, "ext" to mapOf("linkType" to 2.0))))

    // Every entry usable: set as sent, no report.
    val good = logged { m.setExternalUserIds(FakeArray(listOf(id5))) }
    check(good.calls.isEmpty(), "eids good: $good")
    check(prebidEids() == listOf("id5-sync.com" to listOf(Triple("ID5-1", 1, mapOf<String, Any>("linkType" to 2.0)))), "eids good reach Prebid: ${prebidEids()}")

    // Entries without source or uids, and a uid without id, are skipped and
    // counted in one report; the usable ones are set.
    val skips = logged {
        m.setExternalUserIds(
            FakeArray(
                listOf(
                    mapOf("source" to "a.com", "uids" to listOf(mapOf("atype" to 1.0), mapOf("id" to "x"))),
                    mapOf("uids" to emptyList<Any>()),
                    mapOf("source" to "b.com", "uids" to null),
                ),
            ),
        )
    }
    check(skips.sent == listOf("bridge.eids.invalid" to "skipped 2 of 3 eids without source or a uids list, and 1 uids without id"), "eids skips: $skips")
    check(skips.calls == mapOf("bridge.eids.invalid" to 1) && skips.attr("severity") == "warn", "eids skips once: $skips")
    check(prebidEids() == listOf("a.com" to listOf(Triple("x", 0, null))), "eids skips keep the rest: ${prebidEids()}")

    // Only entries skipped, or only uids: each is still reported.
    val entriesOnly = logged { m.setExternalUserIds(FakeArray(listOf(mapOf("source" to "a.com"), id5))) }
    check(entriesOnly.sent == listOf("bridge.eids.invalid" to "skipped 1 of 2 eids without source or a uids list, and 0 uids without id"), "eids entries only: $entriesOnly")
    val uidsOnly = logged { m.setExternalUserIds(FakeArray(listOf(mapOf("source" to "a.com", "uids" to listOf(mapOf("atype" to 3.0)))))) }
    check(uidsOnly.sent == listOf("bridge.eids.invalid" to "skipped 0 of 1 eids without source or a uids list, and 1 uids without id"), "eids uids only: $uidsOnly")
    check(prebidEids() == listOf("a.com" to emptyList<Triple<String, Int?, Map<String, Any>?>>()), "eids uids only: the source is kept: ${prebidEids()}")

    // An entry that is not an object: the list cannot be read, so none are
    // set (Prebid is not called), and it is reported once with the error.
    val before = TargetingParams.externalUserIdCalls
    val unreadable = logged { m.setExternalUserIds(FakeArray(listOf("id5-sync.com"))) }
    check(
        unreadable.sent == listOf("bridge.eids.invalid" to "eids could not be read, so no eids were set: Value for 0 cannot be cast from String to Map"),
        "eids unreadable: $unreadable",
    )
    check(unreadable.calls == mapOf("bridge.eids.invalid" to 1) && unreadable.attr("errName") == "UnexpectedNativeTypeException", "eids unreadable once: $unreadable")
    check(TargetingParams.externalUserIdCalls == before, "eids unreadable: Prebid not called")

    // null and [] clear, with no report.
    check(logged { m.setExternalUserIds(null) }.calls.isEmpty() && prebidEids() == emptyList<Any>(), "eids null clears")
    m.setExternalUserIds(FakeArray(listOf(id5)))
    check(logged { m.setExternalUserIds(FakeArray(emptyList())) }.calls.isEmpty() && prebidEids() == emptyList<Any>(), "eids [] clears")
}

private fun prewarm() {
    val m = module()
    uiQueue().clear()
    // A config it cannot read: reported once (warn), nothing prewarmed.
    val bad = logged { m.prewarm(FakeMap(mapOf("partnerCode" to "fixture", "gamTag" to 5.0))) }
    check(
        bad.sent == listOf("bridge.config.invalid" to "the prewarm config could not be read, so nothing was prewarmed: Value for gamTag cannot be cast from Number to String"),
        "prewarm bad: $bad",
    )
    check(bad.calls == mapOf("bridge.config.invalid" to 1) && bad.attr("severity") == "warn", "prewarm bad once: $bad")
    check(uiQueue().isEmpty(), "prewarm bad: nothing queued")
    // A good config is queued for the UI thread, with no report; null does nothing.
    check(logged { m.prewarm(FakeMap(mapOf("partnerCode" to "fixture"))) }.calls.isEmpty() && uiQueue().size == 1, "prewarm good")
    check(logged { m.prewarm(null) }.calls.isEmpty() && uiQueue().size == 1, "prewarm null")
}

private fun emit() {
    val ctx: ReactContext = context()
    // The React instance is gone: the event is dropped and reported once.
    setJsModule(null)
    val gone = logged { RnEvents.emit(ctx, 7, "onAdLoaded", null) }
    check(gone.sent == listOf("bridge.event_emit.exception" to "onAdLoaded could not reach JS: the React instance is gone"), "emit gone: $gone")
    check(gone.calls == mapOf("bridge.event_emit.exception" to 1) && gone.attr("severity") == "warn", "emit gone once: $gone")

    // The event reaches JS: no report.
    val received = ArrayList<Pair<Int, String?>>()
    setJsModule(
        object : RCTEventEmitter {
            override fun receiveEvent(targetTag: Int, eventName: String?, event: WritableMap?) {
                received += targetTag to eventName
            }
        },
    )
    val sent = logged { RnEvents.emit(ctx, 7, "onFeedLoaded", null) }
    check(sent.calls.isEmpty() && received == listOf(7 to "onFeedLoaded"), "emit reaches JS: $sent $received")
    setJsModule(null)
}

private fun bannerProps() {
    val config = FakeMap(mapOf("partnerCode" to "fixture"))
    val p = BannerProps()
    p.size = "300x250"
    p.zoneId = "43"

    // No config: reported once, however many transactions keep it missing.
    val missing = logged {
        check(p.nextSetUp() == null, "banner no config: no ad")
        check(p.nextSetUp() == null, "banner no config again: no ad")
    }
    check(missing.sent == listOf("bridge.props.invalid" to "the config prop is missing, so no ad was set up"), "banner no config: $missing")
    check(missing.calls == mapOf("bridge.props.invalid" to 1), "banner no config reported once: $missing")
    check(missing.attr("zoneId") == "43" && missing.attr("severity") == "error", "banner no config attrs: $missing")

    // A different problem is reported, once.
    p.config = config
    p.zoneId = null
    val noZone = logged {
        p.nextSetUp()
        p.nextSetUp()
    }
    check(noZone.sent == listOf("bridge.props.invalid" to "the zoneId prop is missing, so no ad was set up") && noZone.calls == mapOf("bridge.props.invalid" to 1), "banner no zone: $noZone")

    // Usable props: the ad is set up once; the same props again set up nothing.
    p.zoneId = "43"
    p.adStack = "gamOnly"
    var setUp: BannerProps.SetUp? = null
    val ready = logged {
        setUp = p.nextSetUp()
        check(p.nextSetUp() == null, "banner same props: no second set up")
    }
    check(ready.calls.isEmpty(), "banner ready: no report: $ready")
    val s = setUp
    check(s != null && s.adSize == AdSize.MREC_300x250 && s.zoneId == "43" && s.adStack == "gamOnly" && s.config.partnerCode == "fixture", "banner set up")
    // New props (another size) set up again.
    p.size = "320x50"
    check(p.nextSetUp()?.adSize == AdSize.BANNER_320x50, "banner new size: set up again")

    // The first problem coming back after usable props is reported again.
    p.config = null
    check(logged { p.nextSetUp() }.calls == mapOf("bridge.props.invalid" to 1), "banner problem back: reported again")

    // A size label JS already reported (ad.size.invalid), or none: no report, no ad.
    val q = BannerProps()
    q.config = config
    q.zoneId = "43"
    for (label in listOf("999x1", null)) {
        q.size = label
        val jsReported = logged { check(q.nextSetUp() == null, "banner label $label: no ad") }
        check(jsReported.calls.isEmpty(), "banner label $label: not reported again: $jsReported")
    }
    // A label JS accepts that has no native size: reported once.
    q.size = "1x1"
    val oneByOne = logged {
        q.nextSetUp()
        q.nextSetUp()
    }
    check(oneByOne.sent == listOf("bridge.props.invalid" to "size 1x1 has no native ad size, so no ad was set up") && oneByOne.calls == mapOf("bridge.props.invalid" to 1), "banner 1x1: $oneByOne")

    // A config it cannot read: reported once (fatal) with the zone, no ad; the
    // same props are not read again.
    val b = BannerProps()
    b.config = FakeMap(mapOf("partnerCode" to "fixture", "gamTag" to 5.0))
    b.size = "320x50"
    b.zoneId = "44"
    val unreadable = logged {
        check(b.nextSetUp() == null, "banner unreadable config: no ad")
        check(b.nextSetUp() == null, "banner unreadable config again: no ad")
    }
    check(
        unreadable.sent == listOf("bridge.config.invalid" to "the config prop could not be read, so no ad was set up: Value for gamTag cannot be cast from Number to String"),
        "banner unreadable config: $unreadable",
    )
    check(unreadable.calls == mapOf("bridge.config.invalid" to 1), "banner unreadable config once: $unreadable")
    check(unreadable.attr("severity") == "fatal" && unreadable.attr("zoneId") == "44", "banner unreadable config attrs: $unreadable")
}

private fun feedProps() {
    val f = FeedProps()
    // No config yet: nothing to set up, nothing to report.
    check(logged { check(f.nextConfig() == null, "feed no config") }.calls.isEmpty(), "feed no config: no report")

    // A config: set up once; the same config again sets up nothing.
    f.config = FakeMap(mapOf("partnerCode" to "fixture", "bannerZid" to "43"))
    var config: SellwildConfig? = null
    val ready = logged {
        config = f.nextConfig()
        check(f.nextConfig() == null, "feed same config: no second set up")
    }
    check(ready.calls.isEmpty() && config?.bannerZid == "43", "feed set up: $ready")

    // A config it cannot read: reported once (fatal), no feed.
    f.config = FakeMap(mapOf("partnerCode" to "fixture", "gamTag" to 5.0))
    val unreadable = logged {
        check(f.nextConfig() == null, "feed unreadable config: no feed")
        check(f.nextConfig() == null, "feed unreadable config again: no feed")
    }
    check(
        unreadable.sent == listOf("bridge.config.invalid" to "the config prop could not be read, so the feed was not set up: Value for gamTag cannot be cast from Number to String"),
        "feed unreadable config: $unreadable",
    )
    check(unreadable.calls == mapOf("bridge.config.invalid" to 1) && unreadable.attr("severity") == "fatal", "feed unreadable config once: $unreadable")
}

private fun configReaders() {
    // Config paths: a wrong-typed geo field still throws (the view manager reports the config), with the fields named.
    val thrown = runCatching { RnGeo.readableMapToGeo(FakeMap(mapOf("lat" to "40.7"))) }.exceptionOrNull()
    check(thrown is IllegalArgumentException && thrown.message == "geo.lat is text, not a number, so it was dropped", "config geo throws: $thrown")
    check(RnGeo.readableMapToGeo(FakeMap(mapOf("city" to "Austin")))?.city == "Austin", "config geo ok")
    check(RnGeo.readableMapToGeo(null) == null, "config geo absent")

    // Feed: core's default zone id 0 (a Double) no longer throws; it is dropped and reported once.
    var cfg: SellwildConfig? = null
    val zero = logged { cfg = SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "bannerZid" to 0.0, "bottomBannerZid" to 7.0))) }
    check(cfg!!.bannerZid == null && cfg!!.bottomBannerZid == null, "numeric zone ids dropped: ${cfg!!.bannerZid}")
    check(zero.sent == listOf("bridge.config.invalid" to "bannerZid is a number, not text, so it was dropped; bottomBannerZid is a number, not text, so it was dropped"), "one report: $zero")
    check(zero.calls == mapOf("bridge.config.invalid" to 1) && zero.attr("severity") == "error", "zone ids reported once: $zero")

    // Text and null zone ids read as before; nothing reported.
    val ok = logged { cfg = SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "bannerZid" to "43", "bottomBannerZid" to null, "mobileBannerZid" to "45", "mobileZids" to listOf("a", null, "b")))) }
    check(cfg!!.bannerZid == "43" && cfg!!.bottomBannerZid == null && cfg!!.mobileBannerZid == "45" && cfg!!.mobileZids == listOf("a", "b"), "text zones: $cfg")
    check(ok.calls.isEmpty(), "no report: $ok")

    // A zone list with a number, or a list that is not one.
    val list = logged { SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "mobileZids" to listOf("a", 5.0)))) }
    check(list.sent == listOf("bridge.config.invalid" to "mobileZids has 1 of 2 entries that are not text, so it was dropped"), "list: $list")
    val notList = logged { SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "mobileZids" to "a,b"))) }
    check(notList.sent == listOf("bridge.config.invalid" to "mobileZids is text, not a list, so it was dropped"), "not list: $notList")

    // Feed: bad zone ids AND an incomplete prebidServer: ONE report naming both, as on iOS.
    val both = logged { cfg = SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "bannerZid" to 0.0, "prebidServer" to mapOf("accountId" to "acct")))) }
    check(both.sent == listOf("bridge.config.invalid" to "bannerZid is a number, not text, so it was dropped; prebidServer has no endpoint text, so the default Prebid Server is used"), "feed one report: $both")
    check(both.calls == mapOf("bridge.config.invalid" to 1) && cfg!!.prebidServer == null, "feed one report once, default pbs: $both")

    // Feed: a prebidServer that is not an object, or has a numeric accountId: reported, default used, the rest applied.
    val pbsText = logged { cfg = SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "bannerZid" to "43", "prebidServer" to "https://pbs"))) }
    check(pbsText.sent == listOf("bridge.config.invalid" to "prebidServer is text, not an object, so the default Prebid Server is used"), "feed pbs text: $pbsText")
    check(cfg!!.bannerZid == "43" && cfg!!.prebidServer == null, "feed pbs text keeps the rest")
    val pbsNumber = logged { SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "prebidServer" to mapOf("accountId" to 12.0, "endpoint" to "https://pbs")))) }
    check(pbsNumber.sent == listOf("bridge.config.invalid" to "prebidServer has no accountId text, so the default Prebid Server is used"), "feed pbs number: $pbsNumber")
    val pbsFull = logged {
        cfg = SellwildFeedViewManager.configFromMap(
            FakeMap(mapOf("partnerCode" to "fixture", "prebidServer" to mapOf("accountId" to "acct", "endpoint" to "https://pbs.example/auction", "bidders" to listOf("ix"), "timeout" to 900.0, "syncEndpoint" to "https://pbs.example/sync"))),
        )
    }
    val server = cfg!!.prebidServer
    check(pbsFull.calls.isEmpty() && server?.accountId == "acct" && server.bidders == listOf("ix") && server.timeout == 900 && server.syncEndpoint == "https://pbs.example/sync", "feed pbs full: $pbsFull $server")
    check(logged { cfg = SellwildFeedViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "prebidServer" to null))) }.calls.isEmpty() && cfg!!.prebidServer == null, "feed pbs null: default, no report")

    // RnPrebidServer on its own: absent and null are the default with no problem.
    check(RnPrebidServer.fromConfig(FakeMap(emptyMap())).let { it.config == null && it.problem == null }, "pbs absent")
    check(RnPrebidServer.fromConfig(FakeMap(mapOf("prebidServer" to null))).let { it.config == null && it.problem == null }, "pbs null")
    check(
        RnPrebidServer.fromConfig(FakeMap(mapOf("prebidServer" to mapOf("accountId" to "a", "endpoint" to "e")))).let {
            it.config?.timeout == 1500 && it.config?.bidders == emptyList<String>() && it.config?.syncEndpoint == null && it.problem == null
        },
        "pbs defaults",
    )

    // Banner: an incomplete prebidServer is reported once, and the default is used.
    var banner: SellwildConfig? = null
    val bannerPbs = logged { banner = SellwildBannerViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "prebidServer" to mapOf("endpoint" to "https://pbs")))) }
    check(bannerPbs.sent == listOf("bridge.config.invalid" to "prebidServer has no accountId text, so the default Prebid Server is used"), "banner pbs: $bannerPbs")
    check(bannerPbs.calls == mapOf("bridge.config.invalid" to 1) && banner!!.prebidServer == null && banner!!.partnerCode == "fixture", "banner default pbs once")
    val bannerOk = logged { banner = SellwildBannerViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "prebidServer" to mapOf("accountId" to "acct", "endpoint" to "https://pbs")))) }
    check(bannerOk.calls.isEmpty() && banner!!.prebidServer?.accountId == "acct", "banner pbs ok: $bannerOk")
    // Banner: a wrong-typed geo field still throws for the caller to report.
    check(runCatching { SellwildBannerViewManager.configFromMap(FakeMap(mapOf("partnerCode" to "fixture", "geo" to mapOf("lat" to "x")))) }.exceptionOrNull() is IllegalArgumentException, "banner geo throws")
}
