import XCTest
import UIKit
@testable import SellwildSDK

/// House-ad image loading: memory cache, disk cache, data: URIs and the
/// download, with each failure reported once. The download and the disk
/// directory are injected; nothing reaches the network.
final class SellwildHouseAdImageTests: FailureCapturingTestCase {

    private var savedLoader: SellwildHouseAd.ImageLoader!
    private var directory: URL!
    private var downloads: [URL] = []

    override func setUp() {
        super.setUp()
        savedLoader = SellwildHouseAd.imageLoader
        SellwildHouseAd.clearMemoryCache()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("house-\(UUID().uuidString)", isDirectory: true)
        downloads = []
    }

    override func tearDown() {
        SellwildHouseAd.imageLoader = savedLoader
        SellwildHouseAd.clearMemoryCache()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// A small real PNG.
    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        }
    }

    private func install(_ result: @escaping (URL) -> Result<Data, Error>, directory: URL? = nil) {
        let dir = directory ?? self.directory
        SellwildHouseAd.imageLoader = SellwildHouseAd.ImageLoader(
            download: { [self] url, completion in
                downloads.append(url)
                completion(result(url))
            },
            directory: { dir }
        )
    }

    private func load(_ url: String) -> UIImage? {
        let done = expectation(description: "loadImage")
        var image: UIImage?
        SellwildHouseAd.loadImage(url) {
            XCTAssertTrue(Thread.isMainThread)
            image = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return image
    }

    // MARK: Download

    func testDownloadIsCachedInMemoryAndOnDisk() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        install { _ in .success(self.png()) }
        let url = "https://cache.sellwild.com/house/a.png"
        XCTAssertEqual(load(url)?.size, UIImage(data: png())?.size)
        XCTAssertEqual(downloads.map(\.absoluteString), [url])
        XCTAssertTrue(FileManager.default.fileExists(atPath: SellwildHouseAd.diskURL(for: url, in: directory).path))

        XCTAssertNotNil(load(url), "memory hit")
        SellwildHouseAd.clearMemoryCache()
        XCTAssertNotNil(load(url), "disk hit")
        XCTAssertEqual(downloads.count, 1, "fetched from the network at most once")
        capture.none()
    }

    func testMemoryHitAnswersSynchronously() throws {
        install { _ in .success(self.png()) }
        let url = "https://cache.sellwild.com/house/sync.png"
        XCTAssertNotNil(load(url))
        var answered: UIImage?
        SellwildHouseAd.loadImage(url) { answered = $0 }
        XCTAssertNotNil(answered)
    }

    func testHTTPErrorIsANetworkFailure() {
        install { _ in .failure(SellwildHouseAd.HTTPStatusError(status: 404)) }
        XCTAssertNil(load("https://cache.sellwild.com/house/missing.png"))
        let event = capture.only(.houseImageNetwork, label: .house)
        XCTAssertEqual(event?.attributes["httpStatus"], "404")
        XCTAssertEqual(event?.attributes["msg"], "HTTP 404")
        XCTAssertEqual(event?.attributes["host"], "cache.sellwild.com")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testTransportErrorIsANetworkFailure() {
        install { _ in .failure(URLError(.timedOut)) }
        XCTAssertNil(load("https://cache.sellwild.com/house/slow.png"))
        XCTAssertEqual(capture.only(.houseImageNetwork, label: .house)?.attributes["errName"], "NSURLErrorDomain(-1001)")
    }

    func testCancelledDownloadIsNotAFailure() throws {
        install { _ in .failure(URLError(.cancelled)) }
        let lines = debugLines { XCTAssertNil(load("https://cache.sellwild.com/house/cancel.png")) }
        XCTAssertEqual(lines, ["[SellwildHouseAd] image download cancelled"])
        capture.none()
    }

    func testBytesThatAreNotAnImage() {
        install { _ in .success(Data("<html/>".utf8)) }
        XCTAssertNil(load("https://cache.sellwild.com/house/html.png"))
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "image data could not be decoded")
    }

    func testURLThatIsNotHTTPIsRefusedBeforeAnyDownload() {
        install { _ in .success(self.png()) }
        XCTAssertNil(load("file:///etc/hosts"))
        XCTAssertTrue(downloads.isEmpty)
        let event = capture.only(.houseImageInvalid, label: .house)
        XCTAssertEqual(event?.attributes["msg"], "image URL is not http(s)")
        XCTAssertEqual(event?.attributes["severity"], "warn")
        XCTAssertNil(event?.attributes["host"])
    }

    func testDiskWriteFailureIsReportedAndTheImageStillShows() throws {
        // The "directory" is a file, so the cache copy cannot be written.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)
        install({ _ in .success(self.png()) }, directory: file)
        XCTAssertNotNil(load("https://cache.sellwild.com/house/write.png"))
        let event = capture.only(.storageWriteException, label: .storage)
        XCTAssertEqual(event?.attributes["msg"]?.hasPrefix("house ad image could not be written to the disk cache"), true)
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    func testNoDiskDirectoryMeansMemoryOnly() {
        SellwildHouseAd.imageLoader = SellwildHouseAd.ImageLoader(
            download: { _, completion in completion(.success(self.png())) },
            directory: { nil }
        )
        XCTAssertNotNil(load("https://cache.sellwild.com/house/memory.png"))
        capture.none()
    }

    // MARK: data: URIs

    func testDataURIIsDecodedInline() {
        install { _ in .failure(PlannedError()) }
        let uri = "data:image/png;base64," + png().base64EncodedString()
        XCTAssertEqual(load(uri)?.size, UIImage(data: png())?.size)
        XCTAssertTrue(downloads.isEmpty)
        capture.none()
    }

    func testDataURIFailures() {
        install { _ in .failure(PlannedError()) }
        XCTAssertNil(load("data:image/png;base64"))
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "data: URI could not be decoded")

        resetCapture()
        XCTAssertNil(load("data:image/png;base64,AAAA"))
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "image data could not be decoded")
    }

    // MARK: Pure parts

    func testDecodeImageRefusesOversizePayloads() {
        guard case .failure(.tooLarge) = SellwildHouseAd.decodeImage(Data(count: SellwildSafeURL.maxImageBytes + 1)) else {
            return XCTFail("over the cap")
        }
        guard case .failure(.undecodableDataURI) = SellwildHouseAd.decodeImage(nil) else { return XCTFail("nil") }
        guard case .success = SellwildHouseAd.decodeImage(png()) else { return XCTFail("a png") }
        XCTAssertEqual(SellwildHouseAd.ImageProblem.tooLarge.rawValue, "image is larger than the 8 MB cap")
    }

    /// The cap is inclusive: exactly `maxImageBytes` is decoded, so these
    /// zero bytes fail as "not an image", not as "too large".
    func testDecodeImageAcceptsExactlyTheCap() {
        guard case .failure(let problem) = SellwildHouseAd.decodeImage(Data(count: SellwildSafeURL.maxImageBytes)) else {
            return XCTFail("zero bytes are not an image")
        }
        XCTAssertEqual(problem, .notAnImage)
    }

    /// An image URL that is not http(s) is a config problem that stays until
    /// the config changes: reported once per launch per URL, not on every
    /// no-fill that shows the backdrop again.
    func testURLThatIsNotHTTPIsReportedOncePerLaunch() {
        install { _ in .success(self.png()) }
        for _ in 0..<3 { XCTAssertNil(load("file:///etc/hosts")) }
        capture.only(.houseImageInvalid, label: .house)

        resetCapture()
        XCTAssertNil(load("file:///etc/hosts"))
        capture.none()
        XCTAssertNil(load("ftp://cache.sellwild.com/house/a.png"))
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "image URL is not http(s)",
                       "another URL is its own report")
        XCTAssertTrue(downloads.isEmpty)
    }

    /// A refused image (a data: URI that does not decode, bytes that are not
    /// an image, a payload over the cap) stays refused until the config or
    /// the listing photo changes: reported once per launch per image. A
    /// failed download can pass next time, so it is reported every time.
    func testRefusedImagesAreReportedOncePerLaunchPerImage() {
        install { url in
            url.lastPathComponent == "big.png" ? .success(Data(count: SellwildSafeURL.maxImageBytes + 1)) : .success(Data("<html/>".utf8))
        }
        let html = "https://cache.sellwild.com/house/html.png"
        for _ in 0..<3 { XCTAssertNil(load(html)) }
        XCTAssertEqual(downloads.count, 3, "every load still tries the download")
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "image data could not be decoded")

        resetCapture()
        for _ in 0..<2 { XCTAssertNil(load("https://cache.sellwild.com/house/big.png")) }
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "image is larger than the 8 MB cap",
                       "another image is its own report")

        resetCapture()
        for _ in 0..<3 { XCTAssertNil(load("data:image/png;base64")) }
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "data: URI could not be decoded")

        resetCapture()
        for _ in 0..<3 { XCTAssertNil(load("data:image/png;base64,AAAA")) }
        let event = capture.only(.houseImageInvalid, label: .house)
        XCTAssertEqual(event?.attributes["msg"], "image data could not be decoded", "another data: URI is its own report")
        XCTAssertNil(event?.attributes["host"], "a data: URI is not sent")

        resetCapture()
        XCTAssertNil(load("data:image/gif;base64,AAAA"))
        XCTAssertEqual(capture.only(.houseImageInvalid, label: .house)?.attributes["msg"], "image data could not be decoded",
                       "the same problem in another data: URI is its own report")

        resetCapture()
        for _ in 0..<2 { XCTAssertNil(load(html)) }
        capture.none()

        newLaunch()
        XCTAssertNil(load(html))
        capture.only(.houseImageInvalid, label: .house)
    }

    func testDownloadFailuresAreReportedEveryTime() {
        install { _ in .failure(SellwildHouseAd.HTTPStatusError(status: 503)) }
        for _ in 0..<2 { XCTAssertNil(load("https://cache.sellwild.com/house/down.png")) }
        XCTAssertEqual(capture.events.map(\.action), [SellwildFailureCode.houseImageNetwork.rawValue],
                       "the dedupe gate folds the repeat into one event")
        XCTAssertEqual(capture.calls, 2, "each failed download is its own report")
    }

    func testDownloadResult() throws {
        let url = try XCTUnwrap(URL(string: "https://cache.sellwild.com/house/a.png"))
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let gone = HTTPURLResponse(url: url, statusCode: 410, httpVersion: nil, headerFields: nil)
        XCTAssertEqual(try SellwildHouseAd.downloadResult(data: Data([1]), response: ok, error: nil).get(), Data([1]))
        XCTAssertEqual(try SellwildHouseAd.downloadResult(data: nil, response: ok, error: nil).get(), Data())
        XCTAssertThrowsError(try SellwildHouseAd.downloadResult(data: nil, response: gone, error: nil).get()) {
            XCTAssertEqual(($0 as? SellwildHouseAd.HTTPStatusError)?.status, 410)
            XCTAssertEqual($0.localizedDescription, "HTTP 410")
        }
        XCTAssertThrowsError(try SellwildHouseAd.downloadResult(data: nil, response: nil, error: PlannedError()).get())
    }

    func testDiskNamesAreStableAcrossLaunches() {
        let dir = URL(fileURLWithPath: "/tmp/house")
        XCTAssertEqual(SellwildHouseAd.diskURL(for: "https://x/a.png", in: dir).lastPathComponent,
                       SellwildHouseAd.diskURL(for: "https://x/a.png", in: dir).lastPathComponent)
        XCTAssertNotEqual(SellwildHouseAd.diskURL(for: "https://x/a.png", in: dir), SellwildHouseAd.diskURL(for: "https://x/b.png", in: dir))
        XCTAssertEqual(SellwildHouseAd.diskURL(for: "", in: dir).lastPathComponent, String(format: "%016llx", UInt64(5381)))
    }

    func testCacheDirectoryIsCreatedOrReported() throws {
        XCTAssertNil(SellwildHouseAd.makeCacheDirectory(in: nil))
        capture.none()

        let made = try XCTUnwrap(SellwildHouseAd.makeCacheDirectory(in: directory))
        XCTAssertEqual(made.lastPathComponent, "SellwildHouseAds")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: made.path, isDirectory: &isDirectory) && isDirectory.boolValue)

        let file = directory.appendingPathComponent("plain-file")
        try Data("x".utf8).write(to: file)
        XCTAssertNil(SellwildHouseAd.makeCacheDirectory(in: file))
        XCTAssertEqual(capture.only(.storageCacheDirException, label: .storage)?.attributes["severity"], "warn")
    }

    func testLiveLoaderDownloadsThroughItsSession() throws {
        let session = StubURLProtocol.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let body = png()
        StubURLProtocol.handler = { _ in .init(status: 200, headers: ["Content-Type": "image/png"], body: body) }
        let loader = SellwildHouseAd.ImageLoader.live(session: session)
        let done = expectation(description: "download")
        var result: Result<Data, Error>?
        loader.download(try XCTUnwrap(URL(string: "https://cache.sellwild.com/house/live.png"))) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(try XCTUnwrap(result).get(), body)
        XCTAssertEqual(SellwildHouseAd.ImageLoader.live().directory()?.lastPathComponent, "SellwildHouseAds",
                       "the live cache lives in Caches/SellwildHouseAds")
    }
}
