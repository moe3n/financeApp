import Foundation

enum Formatters {
    /// Formats a raw amount in its native currency.
    /// Always renders exactly 2 fraction digits (e.g. "$5.00" rather than "$5").
    static func currency(_ amount: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "\(amount) \(code)"
    }

    /// Formats a base-currency amount using the user's base currency.
    static func baseCurrency(_ amount: Double, base: Currency, fx: FXRateStore) -> String {
        currency(amount, code: base.rawValue)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}