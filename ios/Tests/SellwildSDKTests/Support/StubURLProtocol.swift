import Foundation

/// Answers HTTP for one test with no real network. Inject the session from
/// `makeSession()` into the code under test, then set `handler`:
///
///     let session = StubURLProtocol.makeSession()
///     StubURLProtocol.handler = { _ in .init(status: 503) }
///     let client = SellwildAPIClient(session: session)
///
/// Every request is captured in `requests` with its body read into
/// `httpBody` (URLSession hands upload bodies to a protocol as a stream).
/// `NetworkBlocker` resets the handler and the captured requests before each
/// test, and cancels what a test left running on its stub sessions when it
/// ends (`cancelRunningTasks()`), so nothing leaks between tests.
final class StubURLProtocol: URLProtocol {

    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data

        init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        /// A 200 (or `status`) response whose body is `object` as JSON.
        static func json(_ object: Any, status: Int = 200) throws -> Response {
            let body = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
            return Response(status: status, headers: ["Content-Type": "application/json"], body: body)
        }
    }

    /// Builds the response for a request. Throw to fail the request with that
    /// error instead, the way a timeout or a dropped connection would.
    typealias Handler = (URLRequest) throws -> Response

    private static let lock = NSLock()
    private static var currentHandler: Handler?
    private static var captured: [URLRequest] = []
    /// Sessions from `makeSession()` since the last `cancelRunningTasks()`.
    private static var sessions: [URLSession] = []

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return currentHandler }
        set { lock.lock(); defer { lock.unlock() }; currentHandler = newValue }
    }

    /// Requests seen by any stub session, oldest first, bodies included.
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        currentHandler = nil
        captured = []
    }

    /// An ephemeral session that sends every request to this stub and never
    /// to the network or `NetworkBlocker`.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        lock.lock(); defer { lock.unlock() }
        sessions.append(session)
        return session
    }

    /// Cancels every task still open on a session `makeSession()` made since
    /// the last call, and returns once each one is cancelled.
    ///
    /// `NetworkBlocker` calls it when a test ends, before `tearDown()` and
    /// before the next test resets `handler`. URLSession starts a resumed task
    /// a moment later, and on a slow machine that can be after the test. Such
    /// a task (a photo a cell asked for at the end of a test) used to reach
    /// the next test's handler, or none, and its failure was reported into the
    /// next test. Cancelled, it ends as cancelled, which the SDK never
    /// reports. A task the stub already answered keeps that answer.
    static func cancelRunningTasks() {
        lock.lock()
        let open = sessions
        sessions = []
        lock.unlock()
        let group = DispatchGroup()
        for session in open {
            group.enter()
            session.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
                group.leave()
            }
        }
        guard Thread.isMainThread else { return group.wait() }
        // The main run loop keeps turning while it waits, so work that needs
        // the main thread cannot stall the wait.
        while group.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var seen = request
        if seen.httpBody == nil, let stream = seen.httpBodyStream {
            // Setting httpBody also drops the stream, which was read here.
            seen.httpBody = StubURLProtocol.readAll(stream)
        }
        StubURLProtocol.lock.lock()
        StubURLProtocol.captured.append(seen)
        let handler = StubURLProtocol.currentHandler
        StubURLProtocol.lock.unlock()

        guard let handler = handler else {
            let message = "StubURLProtocol has no handler for \(seen.httpMethod ?? "GET") \(seen.url?.absoluteString ?? "<no url>")"
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: message]))
            return
        }
        do {
            let reply = try handler(seen)
            guard let url = seen.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nothing to cancel: startLoading answers before returning.
    }

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
