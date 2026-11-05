// Checks for react-native/ios/SellwildRNBridgeRules.swift: the decisions the
// iOS React Native bridge makes about what JS sent. The rules use Foundation
// only, so they build and run on the Mac with no RN host app. Run by
// native-checks/run.mjs, which compiles this file with the rules.
import Foundation

var failures = 0
var checks = 0

func check(_ ok: Bool, _ name: String, line: UInt = #line) {
    checks += 1
    if !ok {
        failures += 1
        FileHandle.standardError.write("FAIL line \(line): \(name)\n".data(using: .utf8)!)
    }
}

typealias R = SellwildRNBridgeRules
let nativeSizes: Set<String> = ["320x50", "300x250", "728x90", "300x600", "160x600"]
let supports: (String) -> Bool = { nativeSizes.contains($0) }

// bannerPropsProblem
check(R.bannerPropsProblem(hasConfig: true, size: "300x250", zoneId: "43", nativeSupports: supports) == nil, "all good")
check(R.bannerPropsProblem(hasConfig: false, size: "300x250", zoneId: "43", nativeSupports: supports) == "the config prop is missing", "no config")
check(R.bannerPropsProblem(hasConfig: true, size: "300x250", zoneId: nil, nativeSupports: supports) == "the zoneId prop is missing", "no zone")
check(R.bannerPropsProblem(hasConfig: true, size: "1x1", zoneId: "43", nativeSupports: supports) == "size 1x1 has no native ad size", "1x1 is JS-valid, native-missing")
check(R.bannerPropsProblem(hasConfig: true, size: "999x1", zoneId: "43", nativeSupports: supports) == nil, "JS reported a non-AdSize label")
check(R.bannerPropsProblem(hasConfig: true, size: nil, zoneId: "43", nativeSupports: supports) == nil, "JS reported a missing size")
check(R.jsAdSizeLabels == ["300x250", "320x50", "728x90", "160x600", "300x600", "1x1"], "js labels")

// ReportOnce: a props problem is reported when it is not the last one reported.
var once = R.ReportOnce()
check(once.take(nil) == nil, "once: nothing")
check(once.take("a") == "a", "once: first a")
check(once.take("a") == nil, "once: a again")
check(once.take("b") == "b", "once: b")
check(once.take("b") == nil, "once: b again")
check(once.take(nil) == nil && once.last == nil, "once: fine again forgets")
check(once.take("b") == "b", "once: b after fine")

// text
check(R.text(nil, key: "bannerZid") == (nil, nil), "text nil")
check(R.text(NSNull(), key: "bannerZid") == (nil, nil), "text NSNull")
check(R.text("43", key: "bannerZid") == ("43", nil), "text string")
check(R.text(NSNumber(value: 0), key: "bannerZid") == (nil, "bannerZid is a number, not text, so it was dropped"), "text number")
check(R.text(NSNumber(value: true), key: "bannerZid").problem == "bannerZid is a boolean, not text, so it was dropped", "text bool")

// textList
check(R.textList(nil, key: "mobileZids").value == nil && R.textList(nil, key: "mobileZids").problem == nil, "list nil")
check(R.textList(NSNull(), key: "mobileZids").problem == nil, "list null")
check(R.textList(["a", "b"], key: "mobileZids").value == ["a", "b"], "list ok")
check(R.textList(["a", NSNumber(value: 5)] as [Any], key: "mobileZids").problem == "mobileZids has 1 of 2 entries that are not text, so it was dropped", "list mixed")
check(R.textList("a,b", key: "mobileZids").problem == "mobileZids is text, not a list, so it was dropped", "list string")

// prebidServer
check(R.prebidServerProblem(nil) == nil, "pbs nil")
check(R.prebidServerProblem(NSNull()) == nil, "pbs null")
check(R.prebidServerProblem(["accountId": "a", "endpoint": "https://e", "bidders": ["ix"]] as [String: Any]) == nil, "pbs complete")
check(R.prebidServerProblem(["accountId": "a"] as [String: Any]) == "prebidServer has no endpoint text, so the default Prebid Server is used", "pbs no endpoint")
check(R.prebidServerProblem([String: Any]()) == "prebidServer has no accountId or endpoint text, so the default Prebid Server is used", "pbs empty")
check(R.prebidServerProblem(NSNumber(value: 1)) == "prebidServer is a number, not an object, so the default Prebid Server is used", "pbs number")
// An accountId or endpoint that is present but not text counts as missing.
check(R.prebidServerProblem(["accountId": NSNumber(value: 12), "endpoint": "https://e"] as [String: Any]) == "prebidServer has no accountId text, so the default Prebid Server is used", "pbs numeric accountId")
check(R.prebidServerProblem(["accountId": "a", "endpoint": NSNull()] as [String: Any]) == "prebidServer has no endpoint text, so the default Prebid Server is used", "pbs null endpoint")

// remoteJSON: a value JSON cannot hold fails before JSONSerialization can raise.
if case .success(let data) = R.remoteJSON(["CODE": "weatherbug", "N": 48] as NSDictionary) {
    let back = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    check(back["CODE"] as? String == "weatherbug" && back["N"] as? Int == 48, "remote round trip")
} else {
    check(false, "remote valid")
}
if case .failure(let error) = R.remoteJSON(["N": Double.nan] as NSDictionary) {
    check(error is R.RemoteNotJSON, "remote NaN is RemoteNotJSON")
    check("\(error)" == "remote holds a value JSON cannot hold (NaN, infinity or a non-JSON type)", "remote NaN text: \(error)")
} else {
    check(false, "remote NaN fails")
}
if case .failure = R.remoteJSON(["D": Date()] as NSDictionary) {} else { check(false, "remote Date fails") }
if case .failure = R.remoteJSON(["N": Double.infinity] as NSDictionary) {} else { check(false, "remote infinity fails") }

// geoMap (setGeo)
check(R.geoMap(["state": "NY"] as NSDictionary).map["state"] as? String == "NY", "geo ok")
check(R.geoMap(NSDictionary()).problem == nil, "geo empty clears, no problem")
check(R.geoMap(nil).problem == "geo is null, not an object, so geo was cleared", "geo nil")
check(R.geoMap(NSNull()).problem == "geo is null, not an object, so geo was cleared", "geo NSNull")
check(R.geoMap(["NY"]).problem == "geo is a list, not an object, so geo was cleared", "geo list")
check(R.geoMap("NY").map.isEmpty, "geo text clears")
// A field of the wrong type is named; the map passes on as it is, and SellwildGeo(bridged:) drops that field.
let wrongLat = R.geoMap(["state": "NY", "lat": "40.7"] as NSDictionary)
check(wrongLat.map["state"] as? String == "NY" && wrongLat.map["lat"] as? String == "40.7", "geo wrong field passes on")
check(wrongLat.problem == "geo.lat is text, not a number, so it was dropped", "geo lat text: \(wrongLat.problem ?? "nil")")
let wrongMany = R.geoMap(["zip": NSNumber(value: 10001), "country": NSNull(), "lat": NSNull(), "lon": ["x"], "type": NSNumber(value: 2)] as NSDictionary)
check(wrongMany.problem == "geo.zip is a number, not text, so it was dropped; geo.lon is a list, not a number, so it was dropped", "geo many: \(wrongMany.problem ?? "nil")")
check(R.geoMap(["lat": NSNumber(value: 40.7), "lon": NSNumber(value: -74.0), "type": NSNumber(value: 2), "city": "NYC"] as NSDictionary).problem == nil, "geo all typed")
check(R.geoFieldProblem(["metro": ["a": 1]]) == "geo.metro is an object, not text, so it was dropped", "geo metro object")
check(R.geoTextFields == ["country", "state", "city", "zip", "metro"] && R.geoNumberFields == ["lat", "lon", "type"], "geo fields")
// Each field on its own, sent with a type it cannot have, is named.
for key in R.geoTextFields {
    check(R.geoFieldProblem([key: NSNumber(value: 7)]) == "geo.\(key) is a number, not text, so it was dropped", "geo \(key) as a number")
    check(R.geoFieldProblem([key: "x"]) == nil, "geo \(key) as text")
}
for key in R.geoNumberFields {
    check(R.geoFieldProblem([key: "7"]) == "geo.\(key) is text, not a number, so it was dropped", "geo \(key) as text")
    check(R.geoFieldProblem([key: NSNumber(value: 7)]) == nil, "geo \(key) as a number")
}

// configGeoProblem (geo inside a config prop): dropped and named; absent is fine.
check(R.configGeoProblem(nil) == nil && R.configGeoProblem(NSNull()) == nil, "config geo absent")
check(R.configGeoProblem(["city": "Austin"] as [String: Any]) == nil, "config geo ok")
check(R.configGeoProblem(["city": "Austin", "lat": "30.2"] as [String: Any]) == "geo.lat is text, not a number, so it was dropped", "config geo wrong field")
check(R.configGeoProblem("Austin") == "geo is text, not an object, so it was dropped", "config geo text")
check(R.configGeoProblem(["Austin"]) == "geo is a list, not an object, so it was dropped", "config geo list")

// eids
let good: [[String: Any]] = [["source": "id5-sync.com", "uids": [["id": "ID5-1", "atype": 1, "ext": ["linkType": 2]]]]]
let e1 = R.eids(good as NSArray)
check(e1.problem == nil && e1.eids.count == 1 && e1.eids[0].uids[0].id == "ID5-1" && e1.eids[0].uids[0].atype == 1, "eids ok")
check(e1.eids[0].source == "id5-sync.com" && e1.eids[0].uids[0].ext?["linkType"] as? Int == 2, "eids source and ext")
let e2 = R.eids([["source": "a.com", "uids": [["atype": 1], ["id": "x"]]], ["uids": []], ["source": "b.com", "uids": "nope"]] as NSArray)
check(e2.eids.count == 1 && e2.eids[0].uids.count == 1 && e2.eids[0].uids[0].atype == 0, "eids skips")
check(e2.problem == "skipped 2 of 3 eids without source or a uids list, and 1 uids without id", "eids skip text: \(e2.problem ?? "nil")")
// Only uids skipped, or only entries: each is still a problem.
let e4 = R.eids([["source": "a.com", "uids": [["atype": 1], ["id": "x"]]]] as NSArray)
check(e4.eids.count == 1 && e4.eids[0].uids.count == 1, "eids only uids skipped")
check(e4.problem == "skipped 0 of 1 eids without source or a uids list, and 1 uids without id", "eids only uids text: \(e4.problem ?? "nil")")
let e5 = R.eids([["source": "a.com"], ["source": "b.com", "uids": [["id": "y"]]]] as NSArray)
check(e5.eids.count == 1 && e5.problem == "skipped 1 of 2 eids without source or a uids list, and 0 uids without id", "eids only entries: \(e5.problem ?? "nil")")
let e3 = R.eids([["source": "a.com", "uids": []], "x"] as NSArray)
check(e3.eids.isEmpty && e3.problem == "eids has 1 of 2 entries that are not objects, so no eids were set", "eids non-object entry")
check(R.eids(nil).problem == nil && R.eids(NSNull()).problem == nil && R.eids(NSArray()).problem == nil, "eids empty")
check(R.eids(NSDictionary()).problem == "eids is an object, not a list, so no eids were set", "eids object")

// kind
check(R.kind(of: NSNull()) == "null" && R.kind(of: "x") == "text" && R.kind(of: [1]) == "a list", "kind")
check(R.kind(of: NSNumber(value: true)) == "a boolean" && R.kind(of: NSNumber(value: 1)) == "a number", "kind numbers")
check(R.kind(of: NSDictionary()) == "an object" && R.kind(of: Date()) == "Date", "kind object/other: \(R.kind(of: Date()))")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
