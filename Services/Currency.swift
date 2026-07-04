import Foundation

/// Supported currencies. Add more here as needed.
enum Currency: String, CaseIterable, Identifiable, Codable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case inr = "INR"
    case bdt = "BDT"
    case pkr = "PKR"
    case jpy = "JPY"
    case cny = "CNY"
    case aud = "AUD"
    case cad = "CAD"

    var id: String { rawValue }

    var symbol: String {
        let locale = Locale(identifier: "en_US@currency=\(rawValue)")
        return locale.currencySymbol ?? rawValue
    }
}