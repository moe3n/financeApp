import Foundation
import SwiftUI

/// Stores per-currency FX rates against the user's base currency.
/// Rate = how many units of `base` equal 1 unit of `code`.
/// e.g. base = USD, code = EUR, rate = 1.08 means 1 EUR = 1.08 USD.
@MainActor
final class FXRateStore: ObservableObject {
    @AppStorage("FinanceApp.baseCurrency") var baseCurrencyRaw: String = Currency.usd.rawValue

    @Published var rates: [String: Double] {
        didSet { save() }
    }

    private let defaultsKey = "FinanceApp.fxRates"

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: "FinanceApp.fxRates") as? [String: Double] ?? [:]
        // Seed sensible defaults so the app is usable before the user customizes.
        var seeded = saved
        if seeded.isEmpty {
            seeded = [
                "USD": 1.0,
                "EUR": 1.08,
                "GBP": 1.27,
                "INR": 0.012,
                "BDT": 0.0091,
                "PKR": 0.0036,
                "JPY": 0.0064,
                "CNY": 0.14,
                "AUD": 0.66,
                "CAD": 0.74
            ]
        }
        self.rates = seeded
        if saved.isEmpty { save() }
    }

    var base: Currency {
        Currency(rawValue: baseCurrencyRaw) ?? .usd
    }

    func rate(for code: String) -> Double {
        if code == baseCurrencyRaw { return 1.0 }
        return rates[code] ?? 1.0
    }

    /// Convert `amount` in `from` currency to the user's base currency.
    func convertToBase(_ amount: Double, from: String) -> Double {
        if from == baseCurrencyRaw { return amount }
        return amount * rate(for: from)
    }

    private func save() {
        UserDefaults.standard.set(rates, forKey: defaultsKey)
    }
}