import Foundation
import SwiftUI
import SwiftData

/// Computes current net worth (savings + cash − installment remaining) in the
/// user's base currency, plus writes a monthly snapshot so we can show a
/// 6-month history chart. Snapshots are deduplicated by `monthStart` and
/// upserted (last write wins) so changing FX rates later won't pollute
/// older months.
@MainActor
enum NetWorthCalculator {

    /// Months shown in the history chart (excluding current).
    static let historyMonths = 6

    /// Current net worth in base currency. Always uses `fx.convertToBase`.
    static func current(
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        savings: [SavingPlan],
        fx: FXRateStore
    ) -> Double {
        var total: Double = 0

        // Earnings add to net worth (cash on hand, treating app as a ledger).
        for e in earnings {
            total += fx.convertToBase(e.amount, from: e.currencyCode)
        }
        // Spends subtract.
        for s in spends {
            total -= fx.convertToBase(s.amount, from: s.currencyCode)
        }
        // Installments: outstanding principal counts as a liability.
        for i in installments {
            let paid = (i.payments ?? []).reduce(0.0) { $0 + $1.amount }
            let outstanding = max(0, i.principal - paid)
            total -= fx.convertToBase(outstanding, from: i.currencyCode)
        }
        // Savings: amount saved so far counts as an asset.
        for s in savings {
            total += fx.convertToBase(s.savedAmount, from: s.currencyCode)
        }
        return total
    }

    /// Upserts today's snapshot into the given context.
    /// Only writes if there's no existing row for `monthStart`, OR if the
    /// stored value differs by more than `epsilon` from the recomputed value
    /// (so re-launching the app doesn't churn identical rows).
    static func recordSnapshotIfNeeded(
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        savings: [SavingPlan],
        fx: FXRateStore,
        modelContext: ModelContext,
        now: Date = .now,
        epsilon: Double = 0.01,
        calendar: Calendar = .current
    ) {
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return }
        let value = current(
            earnings: earnings,
            spends: spends,
            installments: installments,
            savings: savings,
            fx: fx
        )

        let monthStartStart = monthStart
        let monthStartEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let descriptor = FetchDescriptor<NetWorthSnapshot>(
            predicate: #Predicate { $0.monthStart >= monthStartStart && $0.monthStart < monthStartEnd }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if let row = existing.first {
            if abs(row.value - value) > epsilon {
                row.value = value
                row.recordedAt = now
                try? modelContext.save()
            }
        } else {
            let snap = NetWorthSnapshot(monthStart: monthStart, value: value, recordedAt: now)
            modelContext.insert(snap)
            try? modelContext.save()
        }
    }

    /// Returns up to `historyMonths + 1` (current + previous) snapshots in
    /// chronological order. Missing prior months are back-filled with `nil`
    /// so the chart can render an empty point.
    static func history(snapshots: [NetWorthSnapshot], now: Date = .now, calendar: Calendar = .current)
        -> [(monthStart: Date, value: Double?)]
    {
        var bucket: [Date: Double] = [:]
        for s in snapshots {
            bucket[s.monthStart] = s.value
        }

        guard let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start else {
            return []
        }

        var result: [(Date, Double?)] = []
        for offset in stride(from: historyMonths, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else { continue }
            result.append((date, bucket[date]))
        }
        return result
    }
}