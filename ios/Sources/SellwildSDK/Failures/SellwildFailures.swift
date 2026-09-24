import Foundation

/// How bad a failure is (contracts/FAILURES.md 6.3).
public enum SellwildFailureSeverity: String, CaseIterable {
    /// The surface could not render.
    case fatal
    /// The operation failed and a fallback was used.
    case error
    /// Degraded but handled.
    case warn
}

/// The part of the SDK a failure belongs to. It is the event's `label`.
public enum SellwildFailureComponent: String, CaseIterable {
    case configure, remoteConfig, listings, localized, feed, banner, native, video, house,
         bridge, webview, widget, shorts, tv, flipcard, growthcode, geo, storage
}

/// Reports SDK failures as `clientFailure` events through the existing events
/// queue (`SellwildAPIClient.shared` → events.sellwild.com/events/queue).
/// The contract is contracts/FAILURES.md.
///
///     do {
///         (data, response) = try await session.data(for: request)
///     } catch {
///         SellwildFailures.log(code: .configFetchNetwork, component: .remoteConfig,
///                              error: error, url: url.absoluteString)
///     }
///
/// Log a failure once, at the lowest layer that sees it; callers that only
/// pass a failure on do not log it again. Ad no-fill is not a failure.
///
/// `log` never throws, never waits on the network and never crashes. What it
/// sends is decided by `SellwildFailuresCore` (kill switches, sampling, dedupe
/// and caps). With the SDK debug flag on it prints one line per call. It is
/// one of the two places in the SDK allowed to print (the other is
/// `SellwildLog`).
public enum SellwildFailures {

    /// What every failure event carries (FAILURES.md 3.2).
    public struct Context {
        /// The partner code. `SellwildSDK.configure` sets it before it fetches
        /// the remote config, so config failures carry the partner.
        public var partnerCode: String?
        /// Echo one line per `log` call.
        public var debug = false
        /// Raw remote `EVENTS_ENABLED`. nil (remote config not loaded) is on.
        public var eventsEnabled: Any?
        /// Raw remote `FAILURES_ENABLED`. nil is on.
        public var failuresEnabled: Any?
        /// A local override of `FAILURES_ENABLED`. It wins over the remote value.
        public var failuresEnabledOverride: Bool?
        /// Raw remote `FAILURES_SAMPLE_RATE`. nil is rate 1.
        public var failuresSampleRate: Any?
        /// `react-native` or `flutter` when a wrapper hosts the SDK. Set with
        /// `setWrapper(_:)`.
        public internal(set) var wrapper: String?
        public internal(set) var client = "ios"
        public internal(set) var clientVersion = SellwildSDK.sdkVersion

        /// Whether failures are reported at all: `EVENTS_ENABLED` and the
        /// effective `FAILURES_ENABLED`, both with the contract coercion (5.3).
        public var isEnabled: Bool {
            SellwildFailuresCore.coerceFlag(eventsEnabled) && SellwildFailuresCore.coerceFlag(effectiveFailuresEnabled)
        }

        /// `FAILURES_SAMPLE_RATE` with the contract coercion (5.4), in [0, 1].
        public var sampleRate: Double {
            SellwildFailuresCore.coerceRate(failuresSampleRate)
        }

        private var effectiveFailuresEnabled: Any? {
            if let local = failuresEnabledOverride { return local }
            return failuresEnabled
        }

        var core: SellwildFailuresCore.Context {
            SellwildFailuresCore.Context(
                partnerCode: partnerCode, client: client, clientVersion: clientVersion, wrapper: wrapper,
                release: nil, eventsEnabled: eventsEnabled, failuresEnabled: effectiveFailuresEnabled,
                failuresSampleRate: failuresSampleRate
            )
        }
    }

    /// Where `log` gets its time and uid, and where its events go. Tests swap
    /// them with `setDependencies(_:)`.
    struct Dependencies {
        /// Epoch milliseconds, from the events queue's clock.
        var now: () -> Int64
        /// The events queue uid, so sampling and the wire agree.
        var uid: () -> String
        /// Queues one event.
        var push: (SellwildFailuresCore.Event) throws -> Void
        /// Sends the queue now (first failure of the session, and fatal ones).
        var flush: () throws -> Void
        /// Writes the debug echo.
        var echo: (String) -> Void

        /// The events queue of `client` (the shared one in the SDK; tests pass
        /// one built on a capturing transport) and `print`.
        static func live(client: SellwildAPIClient = .shared) -> Dependencies {
            Dependencies(
                now: { client.eventClock.now() },
                uid: { SellwildSession.shared.uid },
                push: { client.sendEvent(SellwildEvent(failure: $0)) },
                flush: { client.flushEvents() },
                echo: { print($0) }
            )
        }
    }

    // Recursive, so a `setContext` closure may read `context`.
    private static let lock = NSRecursiveLock()
    private static var state = SellwildFailuresCore.State()
    private static var current = Context()
    private static var dependencies = Dependencies.live()
    private static var internalErrors = 0
    private static let loggingKey = "com.sellwild.sdk.failures.logging"

    /// A copy of the current context.
    public static var context: Context {
        locked { current }
    }

    /// Changes the context:
    ///
    ///     SellwildFailures.setContext { $0.failuresEnabledOverride = false }
    ///
    /// The closure edits a copy, so it may read `context` itself.
    public static func setContext(_ update: (inout Context) -> Void) {
        locked {
            var next = current
            update(&next)
            current = next
        }
    }

    /// Marks failures as coming from a wrapper (`react-native` or `flutter`).
    /// The React Native and Flutter bridges call this; any other value is not sent.
    public static func setWrapper(_ wrapper: String?) {
        locked { current.wrapper = wrapper }
    }

    /// Reports one failure. See the type documentation.
    ///
    /// - Parameters:
    ///   - code: The registry code (contracts/failure-codes.json).
    ///   - component: The event label.
    ///   - severity: `.error` unless the surface could not render (`.fatal`) or
    ///     the failure was handled with no visible effect (`.warn`).
    ///   - error: Sent as its type name and localized description, sanitized.
    ///   - message: What failed, without PII. Sanitized and cut to 200.
    ///   - httpStatus: Sent when it is 100–999.
    ///   - url: Only its host is sent.
    ///   - zoneId: The ad zone, when there is one.
    public static func log(
        code: SellwildFailureCode,
        component: SellwildFailureComponent,
        severity: SellwildFailureSeverity = .error,
        error: Error? = nil,
        message: String? = nil,
        httpStatus: Int? = nil,
        url: String? = nil,
        zoneId: String? = nil
    ) {
        // A nested call from inside log (a sink that fails and reports it)
        // returns at once instead of recursing.
        let thread = Thread.current.threadDictionary
        guard thread[loggingKey] == nil else { return }
        thread[loggingKey] = true
        defer { thread.removeObject(forKey: loggingKey) }

        let input = SellwildFailuresCore.Input(
            code: code.rawValue, component: component.rawValue, severity: severity.rawValue,
            errName: error.map(errorName), errMessage: error?.localizedDescription, message: message,
            stack: nil, httpStatus: httpStatus, url: url, zoneId: zoneId
        )
        let (context, deps) = locked { (current, dependencies) }
        do {
            let uid = deps.uid()
            let now = deps.now()
            let decision: SellwildFailuresCore.Decision = locked {
                let decision = SellwildFailuresCore.decide(state: state, input: input, context: context.core, uid: uid, now: now)
                state = decision.state
                return decision
            }
            if context.debug { deps.echo(SellwildFailuresCore.echoLine(input: input, decision: decision)) }
            if let event = decision.event {
                try deps.push(event)
                if decision.flushNow { try deps.flush() }
            }
        } catch let caught {
            // The one failure that is not reported: reporting it would recurse.
            // It is counted for tests and echoed in debug.
            locked { internalErrors += 1 }
            if context.debug {
                deps.echo("[Sellwild] failure internal \(errorName(caught)) \(SellwildFailuresCore.sanitizeMessage(caught.localizedDescription))")
            }
        }
    }

    /// The `errName` of an error (FAILURES.md 3.3): the Swift type name, or
    /// `<domain>(<code>)` for an NSError and for the Foundation types that
    /// wrap one (URLError, CocoaError), e.g. `NSURLErrorDomain(-1001)`.
    static func errorName(_ error: Error) -> String {
        let errorType = type(of: error)
        guard errorType is NSError.Type else { return String(describing: errorType) }
        let ns = error as NSError
        return "\(ns.domain)(\(ns.code))"
    }

    // MARK: Test seams

    /// Errors thrown inside `log` (by the sink) since the last reset.
    static var internalErrorCount: Int {
        locked { internalErrors }
    }

    /// The pure-core state: session count and dedupe keys.
    static var coreState: SellwildFailuresCore.State {
        locked { state }
    }

    static func setDependencies(_ deps: Dependencies) {
        locked { dependencies = deps }
    }

    /// Back to a fresh session: no state, default context, live dependencies
    /// and a zero internal error count. For tests, including a wrapper's own
    /// (FAILURES.md 3.1); the SDK never calls it.
    public static func resetForTests() {
        locked {
            state = SellwildFailuresCore.State()
            current = Context()
            dependencies = .live()
            internalErrors = 0
        }
    }

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension SellwildEvent {
    /// The queue form of a clientFailure event: its uid and createdTime come
    /// from the failure, not from now.
    init(failure: SellwildFailuresCore.Event) {
        self.init(event: failure.event, action: failure.action, label: failure.label,
                  attributes: failure.attributes, uid: failure.uid, createdTime: failure.createdTime)
    }
}
