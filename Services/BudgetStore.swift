import Foundation
import SwiftUI

/// Budget math + lifecycle helpers. Stored as SwiftData `@Model`s in the
/// shared `ModelContainer`, so persistence is automatic; this object only
/// exposes pure functions for spend aggregation.
@MainActor
enum BudgetMath {

    /// Inclusive date interval for the calendar month containing `reference`.
    static func monthInterval(for reference: Date, calendar: Calendar = .current) -> DateInterval {
        if let interval = calendar.dateInterval(of: .month, for: reference) {
            return interval
        }
        // Fallback: start of day through end of month.
        let start = calendar.startOfDay(for: reference)
        let comps = calendar.dateComponents([.year, .month], from: start)
        let monthStart = calendar.date(from: comps) ?? start
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? start
        return DateInterval(start: monthStart, end: monthEnd)
    }

    /// Sum of `spends` whose `category` matches, falling inside `interval`,
    /// converted to `base` currency using `fx`.
    static func spendInCategory(
        _ category: String,
        spends: [Spend],
        interval: DateInterval,
        base: Currency,
        fx: FXRateStore
    ) -> Double {
        var total = 0.0
        for s in spends where s.category == category && interval.contains(s.date) {
            total += fx.convertToBase(s.amount, from: s.currencyCode)
        }
        return total
    }

    /// Convenience for "spent vs. limit" given a budget. Returns 0…∞+ where 1.0
    /// means the user is exactly at the limit, >1.0 means over.
    static func progress(
        for budget: Budget,
        spends: [Spend],
        now: Date,
        base: Currency,
        fx: FXRateStore
    ) -> (spent: Double, limit: Double, ratio: Double) {
        let interval = monthInterval(for: now)
        let spent = spendInCategory(
            budget.category,
            spends: spends,
            interval: interval,
            base: base,
            fx: fx
        )
        let limit = fx.convertToBase(budget.monthlyLimit, from: budget.currencyCode)
        let ratio = limit > 0 ? spent / limit : 0
        return (spent, limit, ratio)
    }
}

/// Lightweight in-memory snapshot used by SwiftUI lists/cards.
struct BudgetSnapshot: Identifiable, Hashable {
    let id: UUID
    let category: String
    let spent: Double
    let limit: Double
    let ratio: Double // spent / limit
    let isOverBudget: Bool
}