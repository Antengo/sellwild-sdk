import Foundation

/// sdkTiming shell (contracts/FAILURES.md section 18.1): records how long a
/// step took, sends the sampled sdkTiming event through the events queue, and
/// logs the step's `*.slow` clientFailure when it is over its budget.
/// Decisions live in `SellwildTimingCore`. Never throws.
enum SellwildTiming {

    /// What the shell talks to. Tests replace it.
    struct Dependencies {
        /// Queues one event.
        var push: (SellwildTimingCore.Event) -> Void
        /// Epoch ms for createdTime.
        var now: () -> Int64
        /// The events queue uid.
        var uid: () -> String
        /// Seconds from a monotonic clock.
        var monotonic: () -> TimeInterval

        static let live = Dependencies(
            push: { event in
                SellwildAPIClient.shared.sendEvent(SellwildEvent(
                    event: event.event, action: event.action, label: event.label,
                    attributes: event.attributes, uid: event.uid, createdTime: event.createdTime
                ))
            },
            now: { SellwildAPIClient.shared.eventClock.now() },
            uid: { SellwildSession.shared.uid },
            monotonic: { ProcessInfo.processInfo.systemUptime }
        )
    }

    private static let lock = NSLock()
    private static var state = SellwildTimingCore.State()
    private static var claimed = Set<String>()
    private static var remoteValues: [String: Any]?
    private static var dependencies = Dependencies.live

    /// The remote config (TIMING_ENABLED, TIMING_SAMPLE_RATE, TIMING_BUDGET_*_MS);
    /// `configure` sets it.
    static var remote: [String: Any]? {
        get { locked { remoteValues } }
        set { locked { remoteValues = newValue } }
    }

    static func setDependencies(_ deps: Dependencies) {
        locked { dependencies = deps }
    }

    /// Seconds on the monotonic clock.
    static func monotonic() -> TimeInterval {
        locked { dependencies }.monotonic()
    }

    /// Records `ms` for `step`: logs `*.slow` when over the budget (not
    /// sampled by timing), then sends the sdkTiming event if this session is
    /// sampled.
    static func record(step: String, ms: Double, zoneId: String? = nil) {
        let (remote, deps) = locked { (remoteValues, dependencies) }
        if let budget = SellwildTimingCore.budgetFor(step, remote: remote), ms > Double(budget),
           let code = SellwildTimingCore.slowCodes[step].flatMap(SellwildFailureCode.init(rawValue:)) {
            let rounded = Int(ms.rounded(.toNearestOrAwayFromZero))
            SellwildFailures.log(code: code, component: component(of: step), severity: .warn,
                                 message: "\(step) took \(rounded) ms", zoneId: zoneId,
                                 context: ["ms": rounded, "budgetMs": budget])
        }
        let failures = SellwildFailures.context
        let context = SellwildTimingCore.Context(
            partnerCode: failures.partnerCode, client: failures.client, clientVersion: failures.clientVersion,
            appId: failures.appId, appVersion: failures.appVersion, os: failures.os, device: failures.device,
            net: nil, eventsEnabled: failures.eventsEnabled,
            timingEnabled: remote?["TIMING_ENABLED"], timingSampleRate: remote?["TIMING_SAMPLE_RATE"]
        )
        let uid = deps.uid()
        let now = deps.now()
        let event: SellwildTimingCore.Event? = locked {
            let decision = SellwildTimingCore.decide(state: state, input: .init(step: step, ms: ms, zoneId: zoneId),
                                                     context: context, uid: uid, now: now)
            state = decision.state
            return decision.event
        }
        if let event { deps.push(event) }
    }

    /// Starts a timer; calling the result records `step` once and returns the ms.
    static func start(_ step: String, zoneId: String? = nil) -> () -> Double {
        let started = monotonic()
        return {
            let ms = (monotonic() - started) * 1000
            record(step: step, ms: ms, zoneId: zoneId)
            return ms
        }
    }

    /// True the first time `key` is claimed in this process:
    /// `feed.firstListing` once, `ad.firstLoad:<zone>` once per zone.
    static func claimOnce(_ key: String) -> Bool {
        locked { claimed.insert(key).inserted }
    }

    private static func component(of step: String) -> SellwildFailureComponent {
        switch step {
        case "config.fetch": return .remoteConfig
        case "listings.fetch": return .listings
        default: return .banner
        }
    }

    /// Back to a fresh process. Tests only.
    static func resetForTests() {
        locked {
            state = SellwildTimingCore.State()
            claimed = []
            remoteValues = nil
            dependencies = .live
        }
    }

    private static func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
