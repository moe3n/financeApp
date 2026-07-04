import Foundation
import SwiftData

/// Money going out. Each spend belongs to a main category (food, transport, …)
/// and optionally a subcategory (groceries, uber, …). Lend/Repay also store a payee.
@Model
final class Spend {
    var id: UUID = UUID()
    var amount: Double = 0
    var currencyCode: String = "USD"
    var date: Date = Date()

    /// Main category raw value (see `SpendCategory`). Stored as String so the
    /// app stays CloudKit-friendly even if you later add a new category.
    var category: String = SpendCategory.food.rawValue

    /// Free-form subcategory like "Groceries", "Uber", "EMI — Bank".
    var subcategory: String = ""

    /// For Lend / Repay — who you lent money to or who you repaid.
    var payee: String = ""

    var note: String = ""

    init(
        amount: Double = 0,
        currencyCode: String = "USD",
        date: Date = Date(),
        category: String = SpendCategory.food.rawValue,
        subcategory: String = "",
        payee: String = "",
        note: String = ""
    ) {
        self.id = UUID()
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.category = category
        self.subcategory = subcategory
        self.payee = payee
        self.note = note
    }
}