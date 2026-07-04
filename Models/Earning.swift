import Foundation
import SwiftData

@Model
final class Earning {
    var id: UUID = UUID()
    var source: String = ""
    var note: String = ""
    var amount: Double = 0
    /// ISO currency code, e.g. "USD".
    var currencyCode: String = "USD"
    var date: Date = Date()
    /// Free-form tag like "Salary", "Freelance", "Gift".
    var category: String = "Salary"

    init(
        source: String = "",
        note: String = "",
        amount: Double = 0,
        currencyCode: String = "USD",
        date: Date = Date(),
        category: String = "Salary"
    ) {
        self.id = UUID()
        self.source = source
        self.note = note
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.category = category
    }
}