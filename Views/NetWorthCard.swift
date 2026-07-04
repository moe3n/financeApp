import SwiftUI
import SwiftData
import Charts

/// Dashboard "Net worth" card. Big headline value + 6-month history chart.
/// On appear, records today's snapshot so the chart grows over time.
struct NetWorthCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fx: FXRateStore

    @Query(sort: \Earning.date, order: .reverse)     private var earnings: [Earning]
    @Query(sort: \Spend.date, order: .reverse)       private var spends: [Spend]
    @Query(sort: \Installment.startDate, order: .reverse) private var installments: [Installment]
    @Query(sort: \SavingPlan.createdAt, order: .reverse)  private var savings: [SavingPlan]
    @Query(sort: \NetWorthSnapshot.monthStart)       private var snapshots: [NetWorthSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Net worth").font(.headline)
                Spacer()
                Text("Last \(NetWorthCalculator.historyMonths + 1) months")
                    .font(.caption).foregroundStyle(.secondary)
            }

            let current = NetWorthCalculator.current(
                earnings: earnings,
                spends: spends,
                installments: installments,
                savings: savings,
                fx: fx
            )
            let history = NetWorthCalculator.history(snapshots: snapshots)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Formatters.currency(current, code: fx.base.rawValue))
                    .font(.title2.weight(.semibold).monospacedDigit())
                Spacer()
                if let change = monthlyChange(history: history) {
                    changePill(change: change)
                }
            }

            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                    if let v = entry.value {
                        LineMark(
                            x: .value("Month", entry.monthStart),
                            y: .value("Value", v)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)

                        AreaMark(
                            x: .value("Month", entry.monthStart),
                            y: .value("Value", v)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortNumber(v))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .frame(height: 140)
        }
        .onAppear {
            NetWorthCalculator.recordSnapshotIfNeeded(
                earnings: earnings,
                spends: spends,
                installments: installments,
                savings: savings,
                fx: fx,
                modelContext: modelContext
            )
        }
    }

    private func monthlyChange(history: [(monthStart: Date, value: Double?)]) -> Double? {
        let values = history.compactMap(\.value)
        guard values.count >= 2 else { return nil }
        return values.last! - values[values.count - 2]
    }

    @ViewBuilder
    private func changePill(change: Double) -> some View {
        let isUp = change >= 0
        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
            Text(Formatters.currency(abs(change), code: fx.base.rawValue))
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule().fill(isUp ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
        )
        .foregroundStyle(isUp ? .green : .red)
    }

    private func shortNumber(_ v: Double) -> String {
        let absV = abs(v)
        switch absV {
        case 1_000_000...:
            return String(format: "%.1fM", v / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", v / 1_000)
        default:
            return String(format: "%.0f", v)
        }
    }
}