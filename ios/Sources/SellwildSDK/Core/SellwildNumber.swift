import Foundation

/// Number conversions for remote values (pure).
enum SellwildNumber {

    /// `value` truncated to an Int and clamped to Int's range, or nil when it
    /// is not finite. `Int(_: Double)` traps on NaN, on infinity and outside
    /// Int's range, and remote config or a sync answer can hold any of them
    /// ("inf" and "nan" are Double text, and a numeric text can be longer than
    /// Int allows). Not finite reads as unset, as in core's `numeric`.
    static func clampedInt(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        // Double(Int.max) rounds up to 2^63, which Int cannot hold.
        if value >= Double(Int.max) { return .max }
        if value <= Double(Int.min) { return .min }
        return Int(value)
    }
}
