import Foundation

/// Reads a MetricKit diagnostic payload (`MXDiagnosticPayload.jsonRepresentation()`)
/// and decides what to report (contracts/FAILURES.md 18.2). Pure: the JSON
/// in, the reports out.
enum SellwildDiagnostics {

    struct Report: Equatable {
        var code: SellwildFailureCode
        var severity: SellwildFailureSeverity
        var message: String
        var stack: String?
    }

    /// Binaries that are the Sellwild SDK or its Prebid fork. MetricKit names
    /// a frame's binary only; a static link puts the SDK inside the app binary.
    static func isSellwildBinary(_ name: String) -> Bool {
        name.hasPrefix("SellwildSDK") || name.hasPrefix("SellwildPrebid")
    }

    static let maxFrames = 30

    /// The reports in one payload: each crash, hang, CPU and disk-write
    /// diagnostic whose call stack has a Sellwild frame. Unreadable JSON → none.
    static func reports(fromJSON data: Data) -> [Report] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return kinds.flatMap { kind in
            (root[kind.key] as? [[String: Any]] ?? []).compactMap { diagnostic -> Report? in
                guard let stack = sellwildStack(diagnostic["callStackTree"] as? [String: Any]) else { return nil }
                let meta = diagnostic["diagnosticMetaData"] as? [String: Any] ?? [:]
                return Report(code: kind.code, severity: kind.severity, message: kind.message(meta), stack: stack)
            }
        }
    }

    /// One kind of MetricKit diagnostic: its key in the payload, its code and
    /// severity, and the text its metadata gives.
    private struct Kind {
        var key: String
        var code: SellwildFailureCode
        var severity: SellwildFailureSeverity
        var message: ([String: Any]) -> String
    }

    private static let kinds = [
        Kind(key: "crashDiagnostics", code: .sdkCrashException, severity: .fatal, message: crashMessage),
        Kind(key: "hangDiagnostics", code: .sdkHangTimeout, severity: .error) {
            "hang: \(text($0["hangDuration"]) ?? "unknown duration")"
        },
        Kind(key: "cpuExceptionDiagnostics", code: .sdkCpuException, severity: .warn) {
            "cpu exception: \(text($0["totalCPUTime"]) ?? "unknown CPU time")"
        },
        Kind(key: "diskWriteExceptionDiagnostics", code: .sdkDiskWriteException, severity: .warn) {
            "disk writes: \(text($0["writesCaused"]) ?? "unknown")"
        }
    ]

    private static func crashMessage(_ meta: [String: Any]) -> String {
        let parts = [
            text(meta["exceptionType"]).map { "exception type \($0)" },
            text(meta["exceptionCode"]).map { "code \($0)" },
            text(meta["signal"]).map { "signal \($0)" },
            text(meta["terminationReason"])
        ].compactMap { $0 }
        return (["crash"] + parts).joined(separator: ": ")
    }

    private static func text(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// The frames of the first call stack that has a Sellwild frame (the
    /// attributed thread first), one `<binary> +<offset>` per line, the
    /// innermost first; nil when no stack has one.
    static func sellwildStack(_ tree: [String: Any]?) -> String? {
        let stacks = tree?["callStacks"] as? [[String: Any]] ?? []
        let attributed = stacks.filter { $0["threadAttributed"] as? Bool == true }
        let ordered = attributed + stacks.filter { $0["threadAttributed"] as? Bool != true }
        for stack in ordered {
            let frames = flatten(stack["callStackRootFrames"] as? [[String: Any]] ?? [])
            if frames.contains(where: { isSellwildBinary($0.binary) }) {
                return frames.prefix(maxFrames).map { "\($0.binary) +\($0.offset)" }.joined(separator: "\n")
            }
        }
        return nil
    }

    /// A MetricKit frame chain, root first: each frame's first sub-frame is
    /// the next one down.
    private static func flatten(_ roots: [[String: Any]]) -> [(binary: String, offset: String)] {
        var out: [(binary: String, offset: String)] = []
        var level = roots
        while let frame = level.first {
            out.append((text(frame["binaryName"]) ?? "?", text(frame["offsetIntoBinaryTextSegment"]) ?? "?"))
            level = frame["subFrames"] as? [[String: Any]] ?? []
        }
        return out
    }
}
