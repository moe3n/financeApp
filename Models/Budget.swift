import Foundation
import SwiftData

/// A monthly spend cap for a single `SpendCategory` (e.g. "Food" → 500 USD).
/// One budget per category — uniqueness is enforced at the store/UI layer
/// because SwiftData's `unique` constraints don't yet work cleanly with
/// `@Model` defaults across iOS 17.
@Model
final class Budget {
    var id: UUID = UUID()
    /// Matches `Spend.category` raw value (e.g. "Food", "Transportation").
    var category: String = ""
    var monthlyLimit: Double = 0
    /// ISO currency code of `monthlyLimit`. Conversions to base happen at read time.
    var currencyCode: String = "USD"
    /// Optional human note ("groceries + lunch", "fuel + uber", …).
    var note: String = ""
    var createdAt: Date = Date()

    init(
        category: String = "",
        monthlyLimit: Double = 0,
        currencyCode: String = "USD",
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.category = category
        self.monthlyLimit = max(0, monthlyLimit)
        self.currencyCode = currencyCode
        self.note = note
        self.createdAt = createdAt
    }
}