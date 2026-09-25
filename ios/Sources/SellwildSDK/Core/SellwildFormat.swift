import UIKit

/// Text and color formatting shared by the feed cards and the house backdrop
/// (pure). One copy of what `SellwildFeedView` and `SellwildHouseAdView` each
/// carried before.
enum SellwildFormat {

    /// The listing price with a currency symbol: "$19315", "€12.50". Empty
    /// when the price is missing or not a number. EUR and GBP get their own
    /// symbol; everything else gets "$".
    static func price(currency: String?, price: String?) -> String {
        guard let price, let value = Double(price) else { return "" }
        let symbol: String
        switch currency?.uppercased() {
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        default: symbol = "$"
        }
        // A whole value too large for an Int (a price of 1e20) used to trap in
        // Int(_:); it now takes the decimal form.
        if value.truncatingRemainder(dividingBy: 1) == 0, let whole = Int(exactly: value) {
            return "\(symbol)\(whole)"
        }
        return String(format: "%@%.2f", symbol, value)
    }

    /// The seller line on a listing card: "FIRST L.  |  sellwild.com", or
    /// "sellwild.com" alone with no seller.
    static func seller(_ user: SellwildUser?) -> String {
        guard let user else { return "sellwild.com" }
        let firstRaw = (user.firstName ?? "").trimmingCharacters(in: .whitespaces)
        let first = firstRaw.isEmpty ? "SELLER" : firstRaw.uppercased()
        guard let lastInitial = user.lastName?.first else { return "\(first)  |  sellwild.com" }
        return "\(first) \(String(lastInitial).uppercased()).  |  sellwild.com"
    }

    /// A color's components, each 0...1.
    struct RGBA: Equatable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        var color: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
    }

    /// "#RRGGBB" or "#RRGGBBAA" (the "#" is optional, spaces around are
    /// ignored), else nil.
    static func hexColor(_ hex: String?) -> RGBA? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let channel = { (shift: UInt64) in CGFloat((v >> shift) & 0xFF) / 255 }
        if s.count == 6 {
            return RGBA(red: channel(16), green: channel(8), blue: channel(0), alpha: 1)
        }
        return RGBA(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    /// `hexColor` as a UIColor.
    static func color(_ hex: String?) -> UIColor? {
        hexColor(hex)?.color
    }

    /// Whether a color reads as dark: Rec. 709 luma under 0.5.
    static func isDark(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5
    }
}
