import XCTest

/// Self-tests for the shared test support code: the network blocker, the HTTP
/// stub, contract fixture loading, and contract output. Every URL here uses
/// the reserved `.invalid` TLD, so even a broken blocker could not reach a
/// real host.

// MARK: - NetworkBlocker

final class NetworkBlockerTests: XCTestCase {

    private func load(_ session: URLSession, _ url: URL) -> (data: Data?, response: URLResponse?, error: Error?) {
        let done = expectation(description: "request finished")
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        session.dataTask(with: url) { data, response, error in
            result = (data, response, error)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        return result
    }

    func testInstalledBeforeAnyTestRan() {
        // The observer saw the bundle start, so it was registered before XCTest
        // ran the first test.
        XCTAssertTrue(NetworkBlocker.sawBundleStart)
        XCTAssertTrue(NetworkBlocker.sessionConfigurationsPatched)
        #if compiler(>=6.3)
        // The image-load hook, not the class-level fallback, installed it, so
        // `-only-testing` runs and parallel clones are covered too.
        XCTAssertEqual(NetworkBlocker.installOrigin, .imageLoad)
        #else
        XCTAssertEqual(NetworkBlocker.installOrigin, .testSuite)
        #endif
    }

    func testSharedSessionRequestIsBlocked() throws {
        let url = URL(string: "https://blocked.invalid/shared?x=1")!
        let result = load(.shared, url)

        XCTAssertNil(result.data)
        XCTAssertNil(result.response)
        let error = try XCTUnwrap(result.error as? URLError)
        XCTAssertEqual(error.code, .notConnectedToInternet)
        XCTAssertTrue(NetworkBlocker.isBlocked(error))
        XCTAssertTrue(error.localizedDescription.contains("GET https://blocked.invalid/shared?x=1"), error.localizedDescription)

        let blocked = NetworkBlocker.takeBlocked()
        XCTAssertEqual(blocked, [
            NetworkBlocker.BlockedRequest(method: "GET", url: url, startedDuring: name),
        ])
        XCTAssertEqual(NetworkBlocker.history.last, blocked.first)
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty, "takeBlocked must claim what it returns")
    }

    func testPostThroughSharedSessionIsBlockedAndRecordsMethod() throws {
        var request = URLRequest(url: URL(string: "https://blocked.invalid/events/queue")!)
        request.httpMethod = "POST"
        request.httpBody = Data("[]".utf8)
        let done = expectation(description: "request finished")
        var failure: Error?
        URLSession.shared.dataTask(with: request) { _, _, error in
            failure = error
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)

        XCTAssertTrue(NetworkBlocker.isBlocked(failure))
        XCTAssertEqual(NetworkBlocker.takeBlocked().map(\.method), ["POST"])
    }

    func testSessionsFromDefaultAndEphemeralConfigurationsAreBlocked() {
        let urls = [
            URL(string: "https://blocked.invalid/default")!,
            URL(string: "http://blocked.invalid/ephemeral")!,
        ]
        let sessions = [
            URLSession(configuration: .default),
            URLSession(configuration: .ephemeral),
        ]
        for (session, url) in zip(sessions, urls) {
            XCTAssertTrue(NetworkBlocker.isBlocked(load(session, url).error), url.absoluteString)
            session.invalidateAndCancel()
        }
        XCTAssertEqual(NetworkBlocker.takeBlocked().map(\.url), urls)
    }

    func testDataContentsOfHTTPIsBlocked() {
        // SellwildHouseAd.loadImage fetches with Data(contentsOf:), which goes
        // through the registered protocol classes rather than a session.
        let url = URL(string: "https://blocked.invalid/house.png")!
        XCTAssertThrowsError(try Data(contentsOf: url))
        XCTAssertEqual(NetworkBlocker.takeBlocked().map(\.url), [url])
    }

    func testLocalFileAndDataURLsPassThrough() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-blocker-\(UUID().uuidString).txt")
        try Data("local".utf8).write(to: file)
        addTeardownBlock { try FileManager.default.removeItem(at: file) }

        XCTAssertEqual(load(.shared, file).data, Data("local".utf8))
        XCTAssertEqual(load(.shared, URL(string: "data:text/plain;base64,aGk=")!).data, Data("hi".utf8))
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty)
    }

    func testIsBlockedRejectsOtherErrors() {
        XCTAssertFalse(NetworkBlocker.isBlocked(nil))
        XCTAssertFalse(NetworkBlocker.isBlocked(URLError(.notConnectedToInternet)))
        XCTAssertFalse(NetworkBlocker.isBlocked(NSError(domain: "x", code: 1)))
    }

    func testUnclaimedFailureMessageNamesEveryRequestAndClaimsThem() throws {
        XCTAssertNil(NetworkBlocker.claimUnclaimedFailureMessage())
        _ = load(.shared, URL(string: "https://blocked.invalid/a")!)
        _ = load(.shared, URL(string: "https://blocked.invalid/b")!)

        let message = try XCTUnwrap(NetworkBlocker.claimUnclaimedFailureMessage())
        XCTAssertTrue(message.contains("2 real network request(s)"), message)
        XCTAssertTrue(message.contains("GET https://blocked.invalid/a (started during \(name))"), message)
        XCTAssertTrue(message.contains("GET https://blocked.invalid/b"), message)
        XCTAssertNil(NetworkBlocker.claimUnclaimedFailureMessage(), "the message claims what it names")
        XCTAssertFalse(message.contains("reported late"), message)
    }

    func testFailureMessageMarksRequestsFromAnotherTestAsLate() throws {
        let url = URL(string: "https://blocked.invalid/late")
        let own = NetworkBlocker.BlockedRequest(method: "GET", url: url, startedDuring: "-[A test]")
        let earlier = NetworkBlocker.BlockedRequest(method: "POST", url: url, startedDuring: "-[A earlier]")
        let between = NetworkBlocker.BlockedRequest(method: "GET", url: nil, startedDuring: nil)

        XCTAssertNil(NetworkBlocker.failureMessage(for: [], currentTest: "-[A test]"))
        let clean = try XCTUnwrap(NetworkBlocker.failureMessage(for: [own], currentTest: "-[A test]"))
        XCTAssertFalse(clean.contains("reported late"), clean)

        let late = try XCTUnwrap(NetworkBlocker.failureMessage(for: [own, earlier, between], currentTest: "-[A test]"))
        XCTAssertTrue(late.contains("3 real network request(s)"), late)
        XCTAssertTrue(late.contains("POST https://blocked.invalid/late (started during -[A earlier])"), late)
        XCTAssertTrue(late.contains("GET <no url> (started between tests)"), late)
        XCTAssertTrue(late.contains("reported late"), late)

        // After the last test nothing is running, so every leftover is late.
        let afterLast = try XCTUnwrap(NetworkBlocker.failureMessage(for: [own], currentTest: nil))
        XCTAssertTrue(afterLast.contains("reported late"), afterLast)
    }

    func testLeftoversFileDefaultsToRepoCoverageTmp() {
        XCTAssertEqual(NetworkBlocker.leftoversFile(environment: [:]).path,
                       Fixtures.repoRoot.path + "/.coverage-tmp/ios-network-leftovers.txt")
        XCTAssertEqual(NetworkBlocker.leftoversFile(environment: ["SELLWILD_NETWORK_LEFTOVERS": ""]).path,
                       Fixtures.repoRoot.path + "/.coverage-tmp/ios-network-leftovers.txt")
        XCTAssertEqual(NetworkBlocker.leftoversFile(environment: ["SELLWILD_NETWORK_LEFTOVERS": "/var/tmp/sw/left.txt"]).path,
                       "/var/tmp/sw/left.txt")
    }

    func testReportLeftoversAppendsAndClaims() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-leftovers-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("nested/leftovers.txt")

        XCTAssertFalse(try NetworkBlocker.reportLeftovers(to: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "nothing is written when nothing is left")

        _ = load(.shared, URL(string: "https://blocked.invalid/first")!)
        XCTAssertTrue(try NetworkBlocker.reportLeftovers(to: file))
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty, "reporting claims the requests")
        _ = load(.shared, URL(string: "https://blocked.invalid/second")!)
        XCTAssertTrue(try NetworkBlocker.reportLeftovers(to: file))

        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("GET https://blocked.invalid/first"), String(lines[0]))
        XCTAssertTrue(lines[1].contains("GET https://blocked.invalid/second"), String(lines[1]))
    }

    func testUnclaimedBlockedRequestFailsTheTest() {
        // The request below is left unclaimed on purpose. The blocker's
        // teardown hook must turn it into a failure of THIS test.
        XCTExpectFailure("NetworkBlocker fails a test that leaves a blocked request unclaimed") { issue in
            issue.compactDescription.contains("https://blocked.invalid/unclaimed")
        }
        XCTAssertTrue(NetworkBlocker.isBlocked(load(.shared, URL(string: "https://blocked.invalid/unclaimed")!).error))
    }
}

// MARK: - StubURLProtocol

final class StubURLProtocolTests: XCTestCase {

    func testStubSessionAnswersFromHandlerAndCapturesBody() throws {
        let session = StubURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        StubURLProtocol.handler = { request in
            try .json(["path": request.url?.path ?? ""], status: 201)
        }
        var request = URLRequest(url: URL(string: "https://stub.invalid/events/queue")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"[{"event":"clientFailure"}]"#.utf8)

        let done = expectation(description: "request finished")
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        session.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)

        XCTAssertNil(result.2)
        let response = try XCTUnwrap(result.1 as? HTTPURLResponse)
        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(result.0)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["path": "/events/queue"])

        let captured = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.httpBody, Data(#"[{"event":"clientFailure"}]"#.utf8))
        XCTAssertTrue(NetworkBlocker.takeBlocked().isEmpty, "a stub session never reaches the blocker")
    }

    func testHandlerErrorFailsTheRequest() {
        let session = StubURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        let done = expectation(description: "request finished")
        var failure: Error?
        session.dataTask(with: URL(string: "https://stub.invalid/slow")!) { _, _, error in
            failure = error
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)

        XCTAssertEqual((failure as? URLError)?.code, .timedOut)
    }

    func testMissingHandlerFailsWithAClearError() {
        let session = StubURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }

        let done = expectation(description: "request finished")
        var failure: Error?
        session.dataTask(with: URL(string: "https://stub.invalid/nohandler")!) { _, _, error in
            failure = error
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)

        XCTAssertEqual((failure as? URLError)?.code, .unsupportedURL)
        XCTAssertTrue(failure?.localizedDescription.contains("no handler for GET https://stub.invalid/nohandler") == true,
                      failure?.localizedDescription ?? "nil")
    }

    func testResetClearsHandlerAndRequests() {
        let session = StubURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        StubURLProtocol.handler = { _ in .init() }
        let done = expectation(description: "request finished")
        session.dataTask(with: URL(string: "https://stub.invalid/reset")!) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)

        StubURLProtocol.reset()
        XCTAssertNil(StubURLProtocol.handler)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}

// MARK: - Fixtures

final class FixturesTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("golden"), withIntermediateDirectories: true)
        try Data(#"{"fv":"1","codes":["config.fetch.http"]}"#.utf8)
            .write(to: root.appendingPathComponent("golden/sample.json"))
        try Data("[1,2]".utf8).write(to: root.appendingPathComponent("list.json"))
        try Data("{nope".utf8).write(to: root.appendingPathComponent("broken.json"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testContractsDirectoryIsInTheRepoRoot() {
        // #filePath resolution: the root holds Package.swift and this file.
        XCTAssertTrue(FileManager.default.fileExists(atPath: Fixtures.repoRoot.appendingPathComponent("Package.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: Fixtures.repoRoot.appendingPathComponent("ios/Tests/SellwildSDKTests/Support/Fixtures.swift").path))
        XCTAssertEqual(Fixtures.contractsDirectory, Fixtures.repoRoot.appendingPathComponent("contracts", isDirectory: true))
        XCTAssertEqual(try Fixtures.url("golden/log-failure.vectors.json").path,
                       Fixtures.repoRoot.path + "/contracts/golden/log-failure.vectors.json")
    }

    func testReadsTheRealContractsDirectoryFromTheSimulator() throws {
        // The events batch schema is a core contract, so it is always there.
        // Reading it proves the host path works inside the simulator, not just
        // in a temp directory.
        let schema = try Fixtures.dict("schemas/events-batch.schema.json")
        XCTAssertEqual(schema["type"] as? String, "array")
    }

    func testDataJsonAndDict() throws {
        XCTAssertEqual(try Fixtures.data("golden/sample.json", root: root), Data(#"{"fv":"1","codes":["config.fetch.http"]}"#.utf8))
        XCTAssertEqual(try Fixtures.json("list.json", root: root) as? [Int], [1, 2])
        let dict = try Fixtures.dict("golden/sample.json", root: root)
        XCTAssertEqual(dict["fv"] as? String, "1")
        XCTAssertEqual(dict["codes"] as? [String], ["config.fetch.http"])
    }

    func testMissingFileNamesTheFullPath() {
        XCTAssertThrowsError(try Fixtures.data("golden/absent.json", root: root)) { error in
            XCTAssertEqual(error as? Fixtures.Failure, .missing(root.appendingPathComponent("golden/absent.json").standardizedFileURL))
            XCTAssertTrue("\(error)".contains("golden/absent.json"))
        }
    }

    func testBrokenJSONAndWrongTopLevelType() {
        XCTAssertThrowsError(try Fixtures.json("broken.json", root: root)) { error in
            guard case .notJSON(let url, _)? = error as? Fixtures.Failure else {
                return XCTFail("expected notJSON, got \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "broken.json")
        }
        XCTAssertThrowsError(try Fixtures.dict("list.json", root: root)) { error in
            XCTAssertEqual(error as? Fixtures.Failure, .notObject(root.appendingPathComponent("list.json").standardizedFileURL))
        }
    }

    func testPathsMayNotLeaveTheContractsDirectory() {
        for path in ["../Package.swift", "golden/../../x.json", "/etc/hosts", ""] {
            XCTAssertThrowsError(try Fixtures.data(path, root: root), path) { error in
                XCTAssertEqual(error as? Fixtures.Failure, .outsideContracts(path))
            }
        }
    }
}

// MARK: - ContractEmitter

final class ContractEmitterTests: XCTestCase {

    private var scratch: URL!
    private var directory: URL!
    private var schemas: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("contract-out-\(UUID().uuidString)", isDirectory: true)
        directory = scratch.appendingPathComponent("out/ios", isDirectory: true)
        schemas = scratch.appendingPathComponent("schemas", isDirectory: true)
        try FileManager.default.createDirectory(at: schemas, withIntermediateDirectories: true)
        for name in ["events-batch", "sample"] {
            try Data("{}".utf8).write(to: schemas.appendingPathComponent("\(name).schema.json"))
        }
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: scratch)
    }

    private func written(_ file: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.fragmentsAllowed])
    }

    func testOutputDirectoryDefaultsToRepoContractsOut() {
        XCTAssertEqual(ContractEmitter.outputDirectory(environment: [:]).path,
                       Fixtures.repoRoot.path + "/contracts/out/ios")
        XCTAssertEqual(ContractEmitter.outputDirectory(environment: ["SELLWILD_CONTRACT_OUT": ""]).path,
                       Fixtures.repoRoot.path + "/contracts/out/ios")
        XCTAssertEqual(ContractEmitter.schemasDirectory.path, Fixtures.repoRoot.path + "/contracts/schemas")
    }

    func testOutputDirectoryHonorsEnvironmentOverride() {
        XCTAssertEqual(ContractEmitter.outputDirectory(environment: ["SELLWILD_CONTRACT_OUT": "/var/tmp/sw-out"]).path,
                       "/var/tmp/sw-out/ios")
    }

    func testEmitWritesSortedJSONNamedBySchemaAndVariant() throws {
        let file = try ContractEmitter.emit(
            ["event": "clientFailure", "attributes": ["fv": "1", "client": "ios"]],
            schema: "events-batch", variant: "client-failure", directory: directory, schemas: schemas)

        XCTAssertEqual(file.lastPathComponent, "events-batch.client-failure.json")
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"attributes\"")).lowerBound,
                          try XCTUnwrap(text.range(of: "\"event\"")).lowerBound, "keys are sorted")
        XCTAssertTrue(text.hasSuffix("}\n"))
        let back = try XCTUnwrap(try written(file) as? [String: Any])
        XCTAssertEqual(back["event"] as? String, "clientFailure")
        XCTAssertEqual(back["attributes"] as? [String: String], ["fv": "1", "client": "ios"])
    }

    func testEmitOverwritesAnEarlierFile() throws {
        try ContractEmitter.emit(["n": 1], schema: "sample", variant: "v", directory: directory, schemas: schemas)
        let file = try ContractEmitter.emit(["n": 2], schema: "sample", variant: "v", directory: directory, schemas: schemas)
        XCTAssertEqual(try written(file) as? [String: Int], ["n": 2])
    }

    func testEmitEncodable() throws {
        struct Sample: Encodable { let url: String; let n: Int }
        let file = try ContractEmitter.emit(encodable: Sample(url: "https://x.invalid/a", n: 2),
                                            schema: "sample", variant: "default", directory: directory, schemas: schemas)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("\"https://x.invalid/a\""), "slashes are not escaped: \(text)")
        XCTAssertEqual((try written(file) as? [String: Any])?["n"] as? Int, 2)
    }

    func testEmitJSONDataChecksItParses() throws {
        let file = try ContractEmitter.emit(jsonData: Data(#"[{"b":1,"a":2}]"#.utf8),
                                            schema: "events-batch", variant: "captured", directory: directory, schemas: schemas)
        XCTAssertEqual(try written(file) as? [[String: Int]], [["a": 2, "b": 1]])

        XCTAssertThrowsError(try ContractEmitter.emit(jsonData: Data("{".utf8), schema: "sample", variant: "y",
                                                      directory: directory, schemas: schemas)) { error in
            guard case .notJSON? = error as? ContractEmitter.Failure else { return XCTFail("expected notJSON, got \(error)") }
        }
    }

    func testEmitRejectsValuesJSONCannotWrite() {
        XCTAssertThrowsError(try ContractEmitter.emit(["when": Date()], schema: "sample", variant: "y",
                                                      directory: directory, schemas: schemas)) { error in
            guard case .notJSON? = error as? ContractEmitter.Failure else { return XCTFail("expected notJSON, got \(error)") }
        }
    }

    func testEmitRejectsBadNamesAndUnknownSchemas() {
        let cases: [(String, String, ContractEmitter.Failure)] = [
            ("../x", "y", .badSchemaName("../x")),
            ("Events", "y", .badSchemaName("Events")),
            ("", "y", .badSchemaName("")),
            ("sample", "a.b", .badVariantName("a.b")),
            ("sample", "-y", .badVariantName("-y")),
            ("sample", "é", .badVariantName("é")),
            ("no-such", "y", .unknownSchema("no-such", schemas.appendingPathComponent("no-such.schema.json"))),
        ]
        for (schema, variant, expected) in cases {
            XCTAssertThrowsError(try ContractEmitter.emit(["a": 1], schema: schema, variant: variant,
                                                          directory: directory, schemas: schemas)) { error in
                XCTAssertEqual(error as? ContractEmitter.Failure, expected)
            }
        }
        XCTAssertNoThrow(try ContractEmitter.emit(["a": 1], schema: "sample", variant: "Upper_and-lower9",
                                                  directory: directory, schemas: schemas))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                       ["sample.Upper_and-lower9.json"], "nothing is written for a rejected name")
    }
}
