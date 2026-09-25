import XCTest
@testable import SellwildSDK

/// Localized (per-state) listings: config resolution with its failure
/// reports, state normalization, the cache URL, the every-Nth math and the
/// seeded merge. The integration object comes from the
/// localized-listings-config factory; listings from the listing factory.
final class SellwildLocalizedListingsTests: FailureCapturingTestCase {

    private func config(_ localized: Any) throws -> SellwildConfig {
        try AppConfigFactory.config(["LOCALIZED_LISTINGS": localized])
    }

    // MARK: resolve

    func testRemoteObjectAndJSONText() throws {
        let object = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config())))
        XCTAssertEqual(object.urlTemplate, "sports-img-data-sm-webp-{state}.json")
        let text = String(decoding: try Factory.data(try LocalizedListingsFactory.config(["frequency": "20", "forceState": "al"])), as: UTF8.self)
        let parsed = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(text)))
        XCTAssertEqual(parsed.frequency, 20)
        XCTAssertEqual(parsed.forceState, "AL")
        capture.none()
    }

    func testFrequencyThatIsMissingOrNotANumberIsZero() throws {
        let noFrequency = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["frequency": Factory.remove]))))
        XCTAssertEqual(noFrequency.frequency, 0)
        let notANumber = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try Factory.offSchema(because: "frequency must be a number or numeric text") {
            try config(try LocalizedListingsFactory.config(["frequency": ["25"]]))
        }))
        XCTAssertEqual(notANumber.frequency, 0)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: notANumber.frequency), 0, "0 turns the dispersion off")
        capture.none()
    }

    /// A frequency too large for an Int (the schema allows any number from 0,
    /// and any run of digits as text) crashed resolve: `Int(_:)` traps. It now
    /// reads as Int.max, which puts a localized listing in every slot, as any
    /// frequency of 100 or more does. Text that reads as infinity or NaN reads
    /// as unset (0), as in core.
    func testFrequencyTooLargeForAnIntIsNotACrash() throws {
        for frequency: Any in [1e19, "99999999999999999999"] {
            let integration = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["frequency": frequency]))))
            XCTAssertEqual(integration.frequency, Int.max, "\(frequency)")
            XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: integration.frequency), 1)
        }
        for text in ["inf", "nan"] {
            let raw = try Factory.offSchema(because: "frequency text must be digits; Double reads \"\(text)\"") {
                try config(try LocalizedListingsFactory.config(["frequency": text]))
            }
            XCTAssertEqual(try XCTUnwrap(SellwildLocalizedListings.resolve(config: raw)).frequency, 0, text)
        }
        capture.none()
    }

    /// The contract's frequency-text fixture: " 12.5 " is numeric text the
    /// schema allows. `Double(_:)` does not trim, so iOS reads it as 0 (the
    /// dispersion is off), with no report, as it always has. Core and Android
    /// read 12.5 (drift/ios.json `other`, localized.frequencyText). Text
    /// without the spaces reads, truncated to a whole percent.
    func testFrequencyTextFixtureWithSpacesReadsAsZero() throws {
        let fixture = Factory.stripMarkers(try Fixtures.dict("fixtures/localized-listings-config/valid/frequency-text.json"))
        XCTAssertEqual(fixture["frequency"] as? String, " 12.5 ")
        let padded = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(fixture)))
        XCTAssertEqual(padded.baseUrl, "https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/")
        XCTAssertEqual(padded.frequency, 0)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: padded.frequency), 0)

        let plain = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["frequency": "12.5"]))))
        XCTAssertEqual(plain.frequency, 12)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: plain.frequency), 8)
        capture.none()
    }

    /// JSON numbers reach the frequency parser as NSNumber: most read as a
    /// Double, an integer a Double cannot hold exactly reads as an Int, and
    /// one too large for an Int reads through NSNumber.
    func testFrequencyNumbersOfEveryWidth() throws {
        let table: [(Any, Int)] = [(25, 25), (12.5, 12), (9_007_199_254_740_993, 9_007_199_254_740_992), (UInt64.max, Int.max)]
        for (frequency, expected) in table {
            let integration = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["frequency": frequency]))))
            XCTAssertEqual(integration.frequency, expected, "\(frequency)")
        }
    }

    /// resolve runs on every feed load. A config that stays unusable is
    /// reported once per launch, per reason.
    func testTheSameProblemIsReportedOncePerLaunch() throws {
        let noBase = try Factory.offSchema(because: "baseUrl must be a URI") {
            try config(try LocalizedListingsFactory.config(["baseUrl": "  "]))
        }
        for _ in 0..<3 { XCTAssertNil(SellwildLocalizedListings.resolve(config: noBase)) }
        capture.only(.localizedConfigInvalid, label: .localized)

        resetCapture()
        let notAnObject = try Factory.offSchema(because: "LOCALIZED_LISTINGS must be an object or its JSON text") { try config(25) }
        for _ in 0..<3 { XCTAssertNil(SellwildLocalizedListings.resolve(config: notAnObject)) }
        XCTAssertNil(SellwildLocalizedListings.resolve(config: noBase))
        XCTAssertEqual(capture.only(.localizedConfigInvalid, label: .localized)?.attributes["msg"], "LOCALIZED_LISTINGS is not an object")

        resetCapture()
        // Any text passes the schema (it cannot say "JSON text of an object").
        let broken = try config("{broken")
        for _ in 0..<2 { XCTAssertNil(SellwildLocalizedListings.resolve(config: broken)) }
        let listText = try config("[1]")
        for _ in 0..<2 { XCTAssertNil(SellwildLocalizedListings.resolve(config: listText)) }
        XCTAssertEqual(capture.events.map(\.action), [SellwildFailureCode.localizedConfigInvalid.rawValue, SellwildFailureCode.localizedConfigInvalid.rawValue])
        XCTAssertEqual(capture.calls, 2)

        resetCapture()
        let unbuildable = try integration(base: "https://cache invalid", template: "s-{state}.json", offSchema: "baseUrl must be a URI")
        for _ in 0..<3 { XCTAssertNil(SellwildLocalizedListings.buildCacheURL(unbuildable, state: "GA")) }
        XCTAssertNil(SellwildLocalizedListings.buildCacheURL(unbuildable, state: "AL"))
        XCTAssertEqual(capture.calls, 2, "once per URL: another state is another URL")
        // The two reports carry the same code and message, so the dedupe gate
        // folds the second into the first event.
        XCTAssertEqual(capture.events.map(\.action), [SellwildFailureCode.localizedUrlInvalid.rawValue])
    }

    func testUnsetAndDisabledAreNotFailures() throws {
        XCTAssertNil(SellwildLocalizedListings.resolve(config: SellwildConfig(partnerCode: "p")))
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try config("")))
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try config("   ")), "blank text is unset too")
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try config("\n\t")))
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try Factory.offSchema(because: "LOCALIZED_LISTINGS null is outside the schema; the SDK reads it as unset") {
            try config(NSNull())
        }))
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.configVariant("disabled-only"))))
        capture.none()
    }

    func testLocalOverrideWinsEntirely() throws {
        var local = try config(try LocalizedListingsFactory.config())
        local.localizedListings = SellwildLocalizedListingsConfig(source: " s ", baseUrl: "https://x.invalid", urlTemplate: "c-{state}.json",
                                                                  frequency: 50, forceState: "tx")
        let integration = try XCTUnwrap(SellwildLocalizedListings.resolve(config: local))
        XCTAssertEqual(integration.baseUrl, "https://x.invalid")
        XCTAssertEqual(integration.source, "s")
        XCTAssertEqual(integration.forceState, "TX")
        local.localizedListings?.enabled = false
        XCTAssertNil(SellwildLocalizedListings.resolve(config: local))
        capture.none()

        local.localizedListings = SellwildLocalizedListingsConfig(enabled: true, baseUrl: "https://x.invalid")
        XCTAssertNil(SellwildLocalizedListings.resolve(config: local))
        capture.only(.localizedConfigInvalid, label: .localized)
    }

    func testMissingBaseURLOrTemplateIsReported() throws {
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try Factory.offSchema(because: "baseUrl must be a URI") {
            try config(try LocalizedListingsFactory.config(["baseUrl": "  "]))
        }))
        let event = capture.only(.localizedConfigInvalid, label: .localized)
        XCTAssertEqual(event?.attributes["msg"], "localized listings need baseUrl and urlTemplate; the feature is off")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testTextThatIsNotAnObjectIsReported() throws {
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try config("{broken")))
        let broken = capture.only(.localizedConfigInvalid, label: .localized)
        XCTAssertEqual(broken?.attributes["msg"]?.hasPrefix("LOCALIZED_LISTINGS text is not valid JSON: "), true)
        XCTAssertEqual(broken?.attributes["errName"], "NSCocoaErrorDomain(3840)")

        resetCapture()
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try config("[1]")))
        XCTAssertEqual(capture.only(.localizedConfigInvalid, label: .localized)?.attributes["msg"], "LOCALIZED_LISTINGS text is not a JSON object")

        resetCapture()
        XCTAssertNil(SellwildLocalizedListings.resolve(config: try Factory.offSchema(because: "LOCALIZED_LISTINGS must be an object or its JSON text") {
            try config(25)
        }))
        XCTAssertEqual(capture.only(.localizedConfigInvalid, label: .localized)?.attributes["msg"], "LOCALIZED_LISTINGS is not an object")
    }

    // MARK: State and URL

    func testStateResolution() throws {
        let integration = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["forceState": Factory.remove]))))
        XCTAssertNil(integration.forceState)
        XCTAssertEqual(SellwildLocalizedListings.resolveState(integration, geoState: " ga "), "GA")
        XCTAssertEqual(SellwildLocalizedListings.normState("US-GA"), "GA", "the trailing two letters of a subdivision")
        XCTAssertEqual(SellwildLocalizedListings.normState("GEORGIA 1"), "GEORGIA 1", "no two-letter tail: the raw upper value")
        XCTAssertNil(SellwildLocalizedListings.normState("  "))
        XCTAssertNil(SellwildLocalizedListings.normState(7))
        let forced = try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["forceState": "al"]))))
        XCTAssertEqual(SellwildLocalizedListings.resolveState(forced, geoState: "GA"), "AL")
    }

    private func integration(base: String, template: String) throws -> SellwildLocalizedListings.Integration {
        try XCTUnwrap(SellwildLocalizedListings.resolve(config: try config(try LocalizedListingsFactory.config(["baseUrl": base, "urlTemplate": template]))))
    }

    /// `integration` for a base or template the schema does not allow.
    private func integration(base: String, template: String, offSchema reason: String) throws -> SellwildLocalizedListings.Integration {
        try Factory.offSchema(because: reason) { try integration(base: base, template: template) }
    }

    func testCacheURLJoinsWithExactlyOneSlash() throws {
        let expected = "https://cache.invalid/sports-ga.json"
        for (base, template) in [("https://cache.invalid", "sports-{state}.json"),
                                 ("https://cache.invalid/", "sports-{state}.json"), ("https://cache.invalid", "/sports-{state}.json")] {
            let url = SellwildLocalizedListings.buildCacheURL(try integration(base: base, template: template), state: "GA")
            XCTAssertEqual(url?.absoluteString, expected, "\(base) + \(template)")
        }
        let upper = try integration(base: "https://cache.invalid/", template: "/sports-{STATE}.json",
                                    offSchema: "the schema spells the token {state}; the SDK matches it in any case")
        XCTAssertEqual(SellwildLocalizedListings.buildCacheURL(upper, state: "GA")?.absoluteString, expected)
        capture.none()
    }

    func testCacheURLThatCannotBeBuiltIsReported() throws {
        XCTAssertNil(SellwildLocalizedListings.buildCacheURL(try integration(base: "https://cache invalid", template: "s-{state}.json",
                                                                             offSchema: "baseUrl must be a URI"), state: "GA"))
        let event = capture.only(.localizedUrlInvalid, label: .localized)
        XCTAssertEqual(event?.attributes["msg"], "localized cache URL could not be built from baseUrl and urlTemplate")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    // MARK: Dispersion

    func testEveryN() {
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 0), 0)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: -5), 0)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 25), 4)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 30), 3)
        // Rounded to the nearest, halves up, as core's Math.round: 100/40 is
        // 2.5 → 3, 100/60 is 1.67 → 2, 100/67 is 1.49 → 1.
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 40), 3)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 60), 2)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 67), 1)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 100), 1)
        XCTAssertEqual(SellwildLocalizedListings.everyN(frequencyPercent: 250), 1)
    }

    private func listings(_ ids: [String]) throws -> [SellwildListing] {
        try ids.map { try ListingFactory.decoded(ListingFactory.make(["id": $0])) }
    }

    func testMergeReplacesEveryNthSlotWithTheSeededShuffle() throws {
        let primary = try listings(["p1", "p2", "p3", "p4", "p5", "p6"])
        let secondary = try listings(["s1", "s2", "p2"])
        var rng = SeededGenerator(seed: 7)
        let merged = SellwildLocalizedListings.merge(primary: primary, secondary: secondary, everyN: 2, using: &rng)

        var replay = SeededGenerator(seed: 7)
        let pool = try listings(["s1", "s2"]).map(\.id).shuffled(using: &replay)
        XCTAssertEqual(merged.map(\.id), ["p1", pool[0], "p3", pool[1], "p5", pool[0]], "de-duped, shuffled, cycled")
        XCTAssertEqual(merged.count, primary.count)

        XCTAssertEqual(SellwildLocalizedListings.merge(primary: primary, secondary: [], everyN: 2).map(\.id), primary.map(\.id))
        XCTAssertEqual(SellwildLocalizedListings.merge(primary: primary, secondary: secondary, everyN: 0).map(\.id), primary.map(\.id))
        XCTAssertEqual(SellwildLocalizedListings.merge(primary: [], secondary: secondary, everyN: 2).map(\.id), [])
        XCTAssertEqual(SellwildLocalizedListings.merge(primary: primary, secondary: try listings(["p1"]), everyN: 2).map(\.id),
                       primary.map(\.id), "nothing left after de-dupe")
        XCTAssertEqual(Set(SellwildLocalizedListings.merge(primary: primary, secondary: secondary, everyN: 3).map(\.id)).isSuperset(of: ["p1", "p2"]), true)
    }
}
