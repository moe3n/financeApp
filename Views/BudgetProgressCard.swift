import SwiftUI
import SwiftData

/// Dashboard card showing this month's progress against every active budget.
/// Hidden entirely when no budgets exist so it doesn't take up space.
struct BudgetProgressCard: View {
    @EnvironmentObject private var fx: FXRateStore

    @Query(sort: \Budget.category) private var budgets: [Budget]
    @Query(sort: \Spend.date, order: .reverse) private var spends: [Spend]

    var body: some View {
        if budgets.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        let snapshots = budgets.map { budget -> BudgetSnapshot in
            let p = BudgetMath.progress(for: budget, spends: spends, now: .now, base: fx.base, fx: fx)
            return BudgetSnapshot(
                id: budget.id,
                category: budget.category,
                spent: p.spent,
                limit: p.limit,
                ratio: p.ratio,
                isOverBudget: p.limit > 0 && p.spent > p.limit
            )
        }
        let totalSpent = snapshots.reduce(0) { $0 + $1.spent }
        let totalLimit = snapshots.reduce(0) { $0 + $1.limit }
        let overCount = snapshots.filter(\.isOverBudget).count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Budgets").font(.headline)
                Spacer()
                Text(monthLabel).font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Formatters.currency(totalSpent, code: fx.base.rawValue))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("of \(Formatters.currency(totalLimit, code: fx.base.rawValue))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if overCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(overCount) over")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                }
            }

            VStack(spacing: 10) {
                ForEach(snapshots.prefix(5)) { s in
                    row(for: s)
                }
                if snapshots.count > 5 {
                    Text("+\(snapshots.count - 5) more in the Budgets tab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(for s: BudgetSnapshot) -> some View {
        let clamped = min(max(s.ratio, 0), 1.5)
        let progress = clamped / 1.5
        let tint: Color = s.isOverBudget ? .red
            : (s.ratio >= 0.85 ? .orange : .accentColor)
        let cat = SpendCategory(rawValue: s.category)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: cat?.symbol ?? "tag.fill")
                    .foregroundStyle(cat?.color ?? .secondary)
                    .frame(width: 18)
                Text(s.category)
                    .font(.subheadline)
                Spacer()
                Text("\(Int((min(s.ratio, 1.5) * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(s.isOverBudget ? .red : .secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: .now)
    }
}