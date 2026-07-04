import Foundation
import SwiftUI
import Charts

// MARK: - Forecast engine

/// One day of the projected running balance.
struct ForecastPoint: Identifiable {
    let date: Date
    let balance: Double
    var id: Date { date }
}

/// Pure-data forecast for the next `days` calendar days.
/// - Starting cash: derived from net of all historical earnings − spends − installment payments.
/// - Income: average daily earnings rate computed from the last 90 days, applied across the window.
/// - Spend: average daily spend rate computed from the last 90 days, applied across the window.
/// - Installments: every scheduled due-date (using the Installment recurrence helpers) subtracts `monthlyAmount`.
enum CashFlowForecast {
    struct Summary {
        let startBalance: Double
        let projectedIncome: Double
        let projectedSpending: Double
        let projectedInstallments: Double
        let endBalance: Double
    }

    /// The default strategy — a 90-day moving average. Swap for `MLStrategy`
    /// or similar without touching the view layer.
    @MainActor
    static var strategy: any ForecastStrategy { _strategy }

    /// `series`-style behaviors also need the per-day installment delta, so
    /// `series(...)` does the math itself once `summary(...)` is back. This
    /// single property is the only configuration surface.
    @MainActor
    static func setStrategy(_ new: any ForecastStrategy) {
        _strategy = new
    }

    @MainActor
    static func summary(
        now: Date = Date(),
        days: Int = 30,
        calendar: Calendar = .current,
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        fx: FXRateStore
    ) -> Summary {
        _strategy.project(
            now: now, days: days, calendar: calendar,
            earnings: earnings, spends: spends, installments: installments, fx: fx
        )
    }

    /// (days+1) daily points — one per day, last point is the final balance.
    /// Distributed income/spending comes from the strategy's `project(...)`
    /// summary; installment deltas land on actual due dates.
    @MainActor
    static func series(
        now: Date = Date(),
        days: Int = 30,
        calendar: Calendar = .current,
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        fx: FXRateStore
    ) -> [ForecastPoint] {
        series(strategy: _strategy, now: now, days: days, calendar: calendar,
               earnings: earnings, spends: spends, installments: installments, fx: fx)
    }

    /// Compute a series using a *specific* strategy instance. Useful for
    /// drawing baseline-vs-active overlays without mutating the global
    /// strategy.
    @MainActor
    static func series(
        strategy: any ForecastStrategy,
        now: Date = Date(),
        days: Int = 30,
        calendar: Calendar = .current,
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        fx: FXRateStore
    ) -> [ForecastPoint] {
        let s = strategy.project(
            now: now, days: days, calendar: calendar,
            earnings: earnings, spends: spends, installments: installments, fx: fx
        )
        guard days > 0 else { return [ForecastPoint(date: now, balance: s.endBalance)] }
        let dailyIncome = s.projectedIncome / Double(days)
        let dailySpend = s.projectedSpending / Double(days)

        // Collect installment deltas by day.
        var installmentByDay: [Date: Double] = [:]
        guard let startOfToday = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let endExclusive = calendar.date(byAdding: .day, value: days, to: startOfToday) else {
            return [ForecastPoint(date: now, balance: s.startBalance)]
        }
        for inst in installments where !inst.isFullyPaid {
            let dates = inst.dueDates(in: startOfToday..<endExclusive, calendar: calendar)
            for d in dates {
                let day = calendar.startOfDay(for: d)
                installmentByDay[day, default: 0] += fx.convertToBase(inst.monthlyAmount, from: inst.currencyCode)
            }
        }

        var points: [ForecastPoint] = []
        var balance = s.startBalance
        for offset in 0...days {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let day = calendar.startOfDay(for: dayDate)
            if offset > 0 {
                balance += dailyIncome
                balance -= dailySpend
                if let hit = installmentByDay[day] {
                    balance -= hit
                }
            }
            points.append(ForecastPoint(date: day, balance: balance))
        }
        return points
    }

    @MainActor
    private static var _strategy: any ForecastStrategy = MovingAverageStrategy()
}

// MARK: - View

struct CashFlowForecastCard: View {
    let now: Date
    let base: Currency
    let fx: FXRateStore
    let summary: CashFlowForecast.Summary
    let points: [ForecastPoint]
    var secondaryPoints: [ForecastPoint]? = nil
    var secondaryLabel: String = ""

    private var delta: Double { summary.endBalance - summary.startBalance }
    private var deltaColor: Color {
        if delta > 0 { return .green }
        if delta < 0 { return .red }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cash-flow forecast").font(.headline)
                Spacer()
                Text("Next 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Powered by \(CashFlowForecast.activeStrategyKind.shortLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("End-of-month balance")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.baseCurrency(summary.endBalance, base: base, fx: fx))
                        .font(.title2.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Net change")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.baseCurrency(delta, base: base, fx: fx))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(deltaColor)
                }
            }

            Chart {
                ForEach(points) { p in
                    AreaMark(
                        x: .value("Day", p.date),
                        y: .value("Balance", p.balance)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Day", p.date),
                        y: .value("Balance", p.balance)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                }
                if let secondaryPoints, !secondaryPoints.isEmpty {
                    ForEach(secondaryPoints) { p in
                        LineMark(
                            x: .value("Day", p.date),
                            y: .value("Balance", p.balance)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(Formatters.baseCurrency(d, base: base, fx: fx))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { v in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .frame(height: 150)

            if let secondaryPoints, !secondaryPoints.isEmpty {
                HStack(spacing: 10) {
                    LegendDot(color: .accentColor, style: .solid)
                    Text("Active: \(CashFlowForecast.activeStrategyKind.shortLabel)")
                        .foregroundStyle(.secondary)
                    LegendDot(color: .secondary, style: .dashed)
                    Text("Baseline: \(secondaryLabel)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                BreakdownRow(label: "Starting balance",
                             amount: summary.startBalance,
                             base: base, fx: fx,
                             color: .secondary)
                BreakdownRow(label: "Projected income",
                             amount: summary.projectedIncome,
                             base: base, fx: fx,
                             color: .green, sign: .plus)
                BreakdownRow(label: "Projected spending",
                             amount: summary.projectedSpending,
                             base: base, fx: fx,
                             color: .red, sign: .minus)
                BreakdownRow(label: "Installments due",
                             amount: summary.projectedInstallments,
                             base: base, fx: fx,
                             color: .orange, sign: .minus)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LegendDot: View {
    enum Style { case solid, dashed }
    let color: Color
    let style: Style

    var body: some View {
        switch style {
        case .solid:
            Capsule().fill(color).frame(width: 14, height: 2)
        case .dashed:
            // Render as three short segments to mimic a dashed line.
            HStack(spacing: 2) {
                Capsule().fill(color).frame(width: 4, height: 2)
                Capsule().fill(color).frame(width: 4, height: 2)
                Capsule().fill(color).frame(width: 4, height: 2)
            }
            .frame(width: 16)
        }
    }
}

private struct BreakdownRow: View {
    enum Sign { case plus, minus }
    let label: String
    let amount: Double
    let base: Currency
    let fx: FXRateStore
    let color: Color
    var sign: Sign = .plus

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text((sign == .minus ? "−" : "+") +
                 Formatters.baseCurrency(amount, base: base, fx: fx))
                .font(.caption.monospacedDigit())
                .foregroundStyle(color == .secondary ? .primary : color)
        }
    }
}
