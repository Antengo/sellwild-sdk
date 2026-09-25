import XCTest
@testable import SellwildSDK

/// Replays contracts/golden/log-failure.vectors.json against the Swift pure
/// core. Every vector must give the same event (or none), flushNow, reason and
/// state as the JS reference. The utf16 vector file is not run: Swift strings
/// cannot hold lone surrogates (FAILURES.md 12.3).
final class SellwildFailuresCoreTests: XCTestCase {

    typealias Core = SellwildFailuresCore

    private func goldenFile() throws -> [String: Any] {
        try Fixtures.dict("golden/log-failure.vectors.json")
    }

    // MARK: Golden vectors

    func testEveryGoldenVectorIsReproducedExactly() throws {
        let file = try goldenFile()
        XCTAssertEqual(file["fv"] as? String, Core.contractVersion)
        let vectors = try XCTUnwrap(file["vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)

        for vector in vectors {
            let name = try XCTUnwrap(vector["name"] as? String)
            let context = try XCTUnwrap(vector["context"] as? [String: Any], name)
            let expected = try XCTUnwrap(vector["expected"] as? [String: Any], name)
            let decision = Core.decide(
                state: try Self.state(vector["stateBefore"]),
                input: Self.input(try XCTUnwrap(vector["input"] as? [String: Any], name)),
                context: Self.context(context),
                uid: context["uid"],
                now: try XCTUnwrap((context["now"] as? NSNumber)?.int64Value, name)
            )
            let actual: [String: Any] = [
                "event": decision.event.map(Self.json) ?? NSNull(),
                "flushNow": decision.flushNow,
                "reason": decision.reason?.rawValue ?? NSNull(),
                "stateAfter": Self.json(decision.state),
            ]
            XCTAssertEqual(try Self.canonical(actual), try Self.canonical(expected), name)

            // The core's own canonical JSON must parse back to the same event.
            if let event = decision.event, let wanted = expected["event"] {
                let parsed = try JSONSerialization.jsonObject(with: Data(Core.canonicalJson(event).utf8))
                XCTAssertEqual(try Self.canonical(parsed), try Self.canonical(wanted), "\(name) canonicalJson")
                XCTAssertEqual(Core.eventByteSize(event), Data(Core.canonicalJson(event).utf8).count)
            }
        }
    }

    func testGoldenLimitsMatchTheCore() throws {
        let limits = try XCTUnwrap(try goldenFile()["limits"] as? [String: Int])
        let core: [String: Int] = [
            "codeMax": Core.Limits.codeMax, "errName": Core.Limits.errName, "msg": Core.Limits.msg,
            "msgBudget": Core.Limits.msgBudget, "msgKey": Core.Limits.msgKey, "stack": Core.Limits.stack,
            "stackFrames": Core.Limits.stackFrames, "zoneId": Core.Limits.zoneId, "host": Core.Limits.host,
            "partnerCode": Core.Limits.partnerCode, "clientVersion": Core.Limits.clientVersion,
            "release": Core.Limits.release, "maxAttributes": Core.attributeKeys.count,
            "eventBytes": Core.Limits.eventBytes, "dedupeWindowMs": Int(Core.Limits.dedupeWindowMs),
            "lruSize": Core.Limits.lruSize, "perKeyEmits": Core.Limits.perKeyEmits,
            "sessionEmits": Core.Limits.sessionEmits,
        ]
        XCTAssertEqual(core, limits)
    }

    // MARK: Unit tables

    private func units(_ name: String) throws -> [[String: Any]] {
        let units = try XCTUnwrap(try goldenFile()["units"] as? [String: Any])
        let table = try XCTUnwrap(units[name] as? [[String: Any]], name)
        XCTAssertFalse(table.isEmpty, name)
        return table
    }

    func testUnitFnv1a32() throws {
        for row in try units("fnv1a32") {
            let expected = try XCTUnwrap(row["expected"] as? NSNumber)
            XCTAssertEqual(Core.fnv1a32(row["input"]), expected.uint32Value, "\(row["input"] ?? "nil")")
        }
    }

    func testUnitTruncateUnicode() throws {
        for row in try units("truncateUnicode") {
            let args = try XCTUnwrap(row["input"] as? [Any])
            let s = try XCTUnwrap(args[0] as? String)
            let max = try XCTUnwrap(args[1] as? Int)
            XCTAssertEqual(Core.truncateUnicode(s, max), row["expected"] as? String, s)
        }
    }

    func testUnitHostOf() throws {
        for row in try units("hostOf") {
            XCTAssertEqual(Core.hostOf(row["input"]), row["expected"] as? String, "\(row["input"] ?? "nil")")
        }
    }

    func testUnitSanitizeMessage() throws {
        for row in try units("sanitizeMessage") {
            XCTAssertEqual(Core.sanitizeMessage(row["input"]), row["expected"] as? String, "\(row["input"] ?? "nil")")
        }
    }

    func testUnitCoerceFlag() throws {
        for row in try units("coerceFlag") {
            let expected = try XCTUnwrap(row["expected"] as? Bool)
            XCTAssertEqual(Core.coerceFlag(row["input"], true), expected, "\(row["input"] ?? "nil")")
        }
    }

    func testUnitCoerceRate() throws {
        for row in try units("coerceRate") {
            let expected = try XCTUnwrap(row["expected"] as? NSNumber)
            XCTAssertEqual(Core.coerceRate(row["input"]), expected.doubleValue, "\(row["input"] ?? "nil")")
        }
    }

    func testUnitNormalizeCode() throws {
        for row in try units("normalizeCode") {
            XCTAssertEqual(Core.normalizeCode(row["input"]), row["expected"] as? String, "\(row["input"] ?? "nil")")
        }
    }

    func testUnitNormalizeHttpStatus() throws {
        for row in try units("normalizeHttpStatus") {
            XCTAssertEqual(Core.normalizeHttpStatus(row["input"]), row["expected"] as? String, "\(row["input"] ?? "nil")")
        }
    }

    // MARK: Cases the vectors do not reach from Swift

    func testSwiftValuesAreReadLikeJSONValues() {
        // The shell passes native Swift values, not NSNumber from JSON.
        XCTAssertFalse(Core.coerceFlag(false))
        XCTAssertTrue(Core.coerceFlag(Int?.none as Any?))
        XCTAssertFalse(Core.coerceFlag(0))
        XCTAssertEqual(Core.coerceRate(true), 1, "a Swift Bool is not the number 1")
        XCTAssertEqual(Core.coerceRate(Double.nan), 1)
        XCTAssertEqual(Core.coerceRate(Double.infinity), 1)
        XCTAssertEqual(Core.coerceRate(NSNull()), 1)
        XCTAssertEqual(Core.normalizeHttpStatus(503), "503")
        XCTAssertNil(Core.normalizeHttpStatus(true))
        XCTAssertNil(Core.normalizeHttpStatus(Int?.none as Any?))
        XCTAssertEqual(Core.normalizeZoneId(-0.0), "0")
        XCTAssertEqual(Core.normalizeZoneId(Int64(9_007_199_254_740_991)), "9007199254740991")
        XCTAssertNil(Core.normalizeZoneId(9_007_199_254_740_992.0), "not a safe integer")
        XCTAssertNil(Core.normalizeZoneId(false))
        XCTAssertNil(Core.normalizeZoneId(["43"]))
        XCTAssertEqual(Core.cleanText(42), "")
    }

    func testRateTextForms() {
        XCTAssertEqual(Core.coerceRate("+.5"), 0.5)
        XCTAssertEqual(Core.coerceRate("0000.25"), 0.25)
        XCTAssertEqual(Core.coerceRate("\t1.\n"), 1)
        XCTAssertEqual(Core.coerceRate("."), 1)
        XCTAssertEqual(Core.coerceRate("+"), 1)
        XCTAssertEqual(Core.coerceRate("1.2.3"), 1)
        XCTAssertEqual(Core.coerceRate("++1"), 1)
        XCTAssertEqual(Core.coerceRate("-0.5"), 1, "a sign other than + is not a rate")
        XCTAssertEqual(Core.coerceRate(0.000001), 0.000001)
    }

    func testNonStringUidAndClientFallBack() throws {
        XCTAssertEqual(Core.fnv1a32(nil), Core.fnv1a32(""))
        XCTAssertEqual(Core.isSampled(uid: nil, rate: 0.2), Core.isSampled(uid: "", rate: 0.2))

        let decision = Core.decide(
            state: .init(),
            input: .init(code: "config.fetch.http", component: "remoteConfig"),
            context: .init(partnerCode: "p", client: "", clientVersion: 7, wrapper: 1, release: " "),
            uid: 12, now: 5
        )
        let event = try XCTUnwrap(decision.event)
        XCTAssertEqual(event.uid, "")
        XCTAssertEqual(event.attributes["code"], "p")
        XCTAssertEqual(event.attributes["client"], "unknown")
        XCTAssertEqual(event.attributes["clientVersion"], "unknown")
        XCTAssertNil(event.attributes["wrapper"])
        XCTAssertNil(event.attributes["release"])
    }

    func testTokenMatchersFollowTheRegexSemantics() {
        func matched(_ token: Core.Token, _ s: String) -> String? {
            let scalars = Array(s.unicodeScalars)
            return Core.match(token, scalars, at: 0).map { String(String.UnicodeScalarView(scalars[0..<$0])) }
        }
        XCTAssertEqual(matched(.url, "git+ssh://a.b/c d"), "git+ssh://a.b/c")
        XCTAssertNil(matched(.url, "1http://a"))
        XCTAssertNil(matched(.url, "http:/a"))
        XCTAssertEqual(matched(.relative, "//cdn-1.x/y)z"), "//cdn-1.x/y")
        XCTAssertNil(matched(.relative, "//.x"))
        XCTAssertNil(matched(.relative, "//abc"))
        XCTAssertNil(matched(.relative, "/x"))
        XCTAssertEqual(matched(.email, "a.b@c.d.ef9"), "a.b@c.d.ef")
        XCTAssertEqual(matched(.email, "a@b.cc.d"), "a@b.cc", "backtracks to the last dot with two letters after it")
        XCTAssertNil(matched(.email, "a@.cc"), "the domain needs a character before the dot")
        XCTAssertNil(matched(.email, "a@b.c"))
        XCTAssertNil(matched(.email, "@b.cc"))
        XCTAssertNil(matched(.email, "ab"))
        XCTAssertEqual(matched(.uuid, "123e4567-e89b-12d3-a456-426614174000x"), "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertNil(matched(.uuid, "123e4567-e89b-12d3-a456-42661417400"))
        XCTAssertNil(matched(.uuid, "123e4567_e89b"))
        XCTAssertEqual(matched(.ipv4, "10.0.0.1234"), "10.0.0.123")
        XCTAssertNil(matched(.ipv4, "1234.0.0.1"))
        XCTAssertNil(matched(.ipv4, "10.0.0"))
        XCTAssertNil(matched(.ipv4, "10..0.1"))
        XCTAssertEqual(matched(.digits, "1234567a"), "1234567")
        XCTAssertNil(matched(.digits, "12345"))
        XCTAssertEqual(matched(.path, "/a/b/c.js:1"), "/a/b/")
        XCTAssertNil(matched(.path, "c.js:1"))
        XCTAssertEqual(matched(.query, "?v=1:2"), "?v=1")
        XCTAssertNil(matched(.query, "v"))
    }

    func testHostOfUnclosedIPv6LiteralHasNoHost() {
        XCTAssertNil(Core.hostOf("http://[::1/x"))
        XCTAssertEqual(Core.hostOf("http://[::1]:8080/x"), "<ip>")
    }

    func testStackHelpersForDirectCallers() {
        // decide never passes an empty errName, but the reference treats "" as absent.
        XCTAssertEqual(Core.sanitizeStack(":x\ny", errName: ""), ":x\ny")
        XCTAssertEqual(Core.sanitizeStack("E\nat f (x.js:1)", errName: "E"), "at f (x.js:1)")
        XCTAssertNil(Core.sanitizeStack(" \n\r\n", errName: nil))
        XCTAssertNil(Core.sanitizeStack(42, errName: nil))
        XCTAssertEqual(Core.sanitizeStack("at file:///", errName: nil), "at <url>", "no host and no basename")
        XCTAssertEqual(Core.sanitizeStack("at u@example.com 123e4567-e89b-12d3-a456-426614174000 10.1.2.3", errName: nil),
                       "at <email> <id> <ip>")
    }

    func testCanonicalJsonEscapesLikeTheReference() {
        let event = Core.Event(event: "e", action: "a", label: "l", attributes: ["msg": "q\"b\\s/é"],
                               uid: "\u{8}\u{C}\n\r\t\u{1}\u{1F}", createdTime: 1_790_000_000_000)
        XCTAssertEqual(Core.canonicalJson(event),
                       #"{"event":"e","action":"a","label":"l","attributes":{"msg":"q\"b\\s/é"},"uid":"\b\f\n\r\t\u0001\u001f","createdTime":1790000000000}"#)
        XCTAssertEqual(Core.eventByteSize(event), Core.canonicalJson(event).utf8.count)
    }

    func testTruncateNeverCrashesAndSameIsCodePointEquality() {
        // Callers only pass the positive limits; a zero limit must still not trap.
        XCTAssertEqual(Core.truncateUnicode("abc", 0), "…")
        // Swift's == says these are equal; JS === and the core say they are not.
        XCTAssertFalse(Core.same("e\u{301}", "é"))
        XCTAssertFalse(Core.same("\u{212A}", "K"))
        XCTAssertTrue(Core.same("K", "K"))
    }

    func testEchoLine() {
        let input = Core.Input(code: "config.fetch.http", component: "remoteConfig", severity: "warn",
                               message: "HTTP 403 for jane@example.com")
        let sent = Core.Decision(state: .init(), event: nil, flushNow: false, reason: nil)
        XCTAssertEqual(Core.echoLine(input: input, decision: sent),
                       "[Sellwild] failure config.fetch.http remoteConfig warn sent HTTP 403 for <email>")
        let dropped = Core.Decision(state: .init(), event: nil, flushNow: false, reason: .sampledOut)
        XCTAssertEqual(Core.echoLine(input: .init(code: "Bad", component: nil), decision: dropped),
                       "[Sellwild] failure client.code.invalid unknown error sampled_out")
    }

    // MARK: JSON helpers

    static func input(_ d: [String: Any]) -> Core.Input {
        Core.Input(code: d["code"], component: d["component"], severity: d["severity"], errName: d["errName"],
                   errMessage: d["errMessage"], message: d["message"], stack: d["stack"],
                   httpStatus: d["httpStatus"], url: d["url"], zoneId: d["zoneId"])
    }

    static func context(_ d: [String: Any]) -> Core.Context {
        Core.Context(partnerCode: d["partnerCode"], client: d["client"], clientVersion: d["clientVersion"],
                     wrapper: d["wrapper"], release: d["release"], eventsEnabled: d["eventsEnabled"],
                     failuresEnabled: d["failuresEnabled"], failuresSampleRate: d["failuresSampleRate"])
    }

    static func state(_ any: Any?) throws -> Core.State {
        let d = try XCTUnwrap(any as? [String: Any])
        let keys = try XCTUnwrap(d["keys"] as? [[String: Any]]).map { k in
            Core.KeyEntry(key: try XCTUnwrap(k["key"] as? String),
                          lastEmitAt: try XCTUnwrap((k["lastEmitAt"] as? NSNumber)?.int64Value),
                          suppressed: try XCTUnwrap(k["suppressed"] as? Int),
                          emits: try XCTUnwrap(k["emits"] as? Int))
        }
        return Core.State(sessionCount: try XCTUnwrap(d["sessionCount"] as? Int), keys: keys)
    }

    static func json(_ event: Core.Event) -> [String: Any] {
        ["event": event.event, "action": event.action, "label": event.label, "attributes": event.attributes,
         "uid": event.uid, "createdTime": event.createdTime]
    }

    static func json(_ state: Core.State) -> [String: Any] {
        ["sessionCount": state.sessionCount,
         "keys": state.keys.map { ["key": $0.key, "lastEmitAt": $0.lastEmitAt, "suppressed": $0.suppressed, "emits": $0.emits] }]
    }

    /// Sorted-key JSON text, so two values compare equal exactly when their
    /// JSON is the same.
    static func canonical(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}
