import SwiftUI
import SwiftData
import Charts

/// Phase E1 — dedicated screen for *understanding* the data the rest of the app
/// collects. Three charts + a burn-rate headline:
///
/// 1. Bar chart of income vs spending for the last 6 calendar months.
/// 2. Category breakdown pie for the current month.
/// 3. List of the biggest spends this month (so you can see *what* drove the
///    burn-rate, not just *how much*).
/// 4. A burn-rate headline: average daily spend so far this month, extrapolated
///    to a full month, plus the most recent rolling 30-day average for context.
///
/// Aggregations live in this file so it's easy to read; if they grow we can lift
/// them into a `Services/InsightsAggregator.swift` later.
struct InsightsView: View {
    @EnvironmentObject private var fx: FXRateStore

    @Query(sort: \Earning.date, order: .reverse) private var earnings: [Earning]
    @Query(sort: \Spend.date, order: .reverse) private var spends: [Spend]

    private var calendar: Calendar { Calendar.current }

    // MARK: - Buckets

    /// One month's totals, in base currency. Mirrors `DashboardView.MonthBucket`
    /// but trimmed to income vs spending (the only two things the Insights tab
    /// shows side-by-side).
    fileprivate struct MonthBucket: Identifiable {
        let id: Date          // first day of the month
        let label: String     // "Jan", "Feb", …
        let earned: Double
        let spent: Double
    }

    /// Last 6 calendar months, oldest first. Built the same way Dashboard does
    /// (start from now, walk back six month-starts, aggregate).
    private var last6Months: [MonthBucket] {
        let now = Date()
        let months: [Date] = (0..<6).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: calendar.startOfDay(for: now))
        }
        return months.map { monthStart in
            let inMonth: (Date) -> Bool = {
                calendar.isDate($0, equalTo: monthStart, toGranularity: .month)
            }
            let earned = earnings
                .filter { inMonth($0.date) }
                .reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            let spent = spends
                .filter { inMonth($0.date) }
                .reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            return MonthBucket(
                id: monthStart,
                label: monthLabel(monthStart),
                earned: earned,
                spent: spent
            )
        }
    }

    // MARK: - Current-month slices

    /// Spends whose date falls inside the current calendar month.
    private var monthSpends: [Spend] {
        spends.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    /// Spend grouped by main category for the pie chart. Sorted by amount desc
    /// so the largest wedge renders first in the legend.
    private var spendByCategory: [(SpendCategory, Double)] {
        let grouped = Dictionary(grouping: monthSpends, by: { SpendCategory(rawValue: $0.category) ?? .extra })
        return SpendCategory.allCases.compactMap { c in
            guard let items = grouped[c], !items.isEmpty else { return nil }
            let total = items.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            return (c, total)
        }
        .sorted { $0.1 > $1.1 }
    }

    /// The 5 largest spends in the current month, converted to base currency.
    /// `baseAmount` is precomputed so the row doesn't repeat the FX conversion.
    fileprivate struct BigSpend: Identifiable {
        let id: UUID
        let date: Date
        let category: SpendCategory
        let label: String
        let nativeAmount: Double
        let nativeCurrency: String
        let baseAmount: Double
    }

    private var biggestSpends: [BigSpend] {
        monthSpends
            .map { s -> BigSpend in
                let cat = SpendCategory(rawValue: s.category) ?? .extra
                return BigSpend(
                    id: s.id,
                    date: s.date,
                    category: cat,
                    label: s.subcategory.isEmpty ? cat.rawValue : s.subcategory,
                    nativeAmount: s.amount,
                    nativeCurrency: s.currencyCode,
                    baseAmount: fx.convertToBase(s.amount, from: s.currencyCode)
                )
            }
            .sorted { $0.baseAmount > $1.baseAmount }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Burn rate

    /// Headline burn-rate number: average daily spend so far this month, scaled
    /// up to a full calendar month. This is the "if you keep going at this pace
    /// you'll spend $X in total" figure — the most actionable number on the
    /// screen. Returns `nil` when there are no spends yet (so we can show a
    /// friendly placeholder instead of "$0.00").
    private var projectedMonthSpend: Double? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: Date()) else {
            return nil
        }
        let dayOfMonth = calendar.dateComponents([.day], from: monthInterval.start, to: Date()).day ?? 0
        let spentSoFar = monthSpends
            .reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthInterval.start)?.count ?? 30
        // Burn rate counts from day 1; if we're on day 0 (start of day on the 1st),
        // avoid divide-by-zero — fall back to spentSoFar as a flat projection.
        guard dayOfMonth >= 1 else { return spentSoFar }
        let dailyAverage = spentSoFar / Double(dayOfMonth)
        return dailyAverage * Double(daysInMonth)
    }

    /// Rolling 30-day average daily spend across the trailing window. Used as a
    /// "normal pace" reference next to the projection.
    private var trailing30DayDailyAverage: Double? {
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -30, to: end) else { return nil }
        let windowSpends = spends.filter { ($0.date >= start) && ($0.date <= end) }
        let total = windowSpends.reduce(0.0) {
            fx.convertToBase($1.amount, from: $1.currencyCode) + $0
        }
        // Use exactly 30 days as the divisor (not the actual days between
        // `start` and `end`) so the value is comparable month-over-month.
        return total / 30.0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BurnRateCard(
                        projectedMonthSpend: projectedMonthSpend,
                        trailing30DayDailyAverage: trailing30DayDailyAverage,
                        spentSoFarThisMonth: monthSpends.reduce(0.0) {
                            fx.convertToBase($1.amount, from: $1.currencyCode) + $0
                        },
                        base: fx.base,
                        fx: fx
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Burn rate")
                }

                Section("Income vs spending — last 6 months") {
                    IncomeVsSpendingChart(buckets: last6Months, base: fx.base)
                }

                if !spendByCategory.isEmpty {
                    Section("This month — by category") {
                        CategoryBreakdownPie(rows: spendByCategory, base: fx.base, fx: fx)
                    }
                }

                Section("Biggest spends this month") {
                    if biggestSpends.isEmpty {
                        Text("No spends yet this month").foregroundStyle(.secondary)
                    } else {
                        ForEach(biggestSpends) { row in
                            BiggestSpendRow(row: row, base: fx.base, fx: fx)
                        }
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }

    // MARK: - Helpers

    private func monthLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: d)
    }
}

// MARK: - Burn rate card

/// The headline "how fast are you spending?" tile. Three numbers:
/// - Projected month-end total spend (burn rate × days in month).
/// - Trailing 30-day daily average, for a "normal pace" comparison.
/// - Spent so far this month, as raw context.
private struct BurnRateCard: View {
    let projectedMonthSpend: Double?
    let trailing30DayDailyAverage: Double?
    let spentSoFarThisMonth: Double
    let base: Currency
    let fx: FXRateStore

    private var projectionSubtitle: String {
        guard let projected = projectedMonthSpend else { return "Add a spend to see your pace" }
        let delta = projected - spentSoFarThisMonth
        if spentSoFarThisMonth <= 0 { return "Projected end of month" }
        if abs(delta) < 0.5 { return "Projected end of month — on track" }
        let more = delta > 0
        return more
            ? "Projected: +\(Formatters.currency(delta, code: base.rawValue)) more this month"
            : "Projected: \(Formatters.currency(delta, code: base.rawValue)) under pace"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(projectedMonthSpend.map { Formatters.currency($0, code: base.rawValue) } ?? "—")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                Spacer()
                if let daily = trailing30DayDailyAverage {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatters.currency(daily, code: base.rawValue) + "/day")
                            .font(.subheadline.monospacedDigit())
                        Text("30-day avg").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Text(projectionSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Spent so far")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.currency(spentSoFarThisMonth, code: base.rawValue))
                    .font(.caption.monospacedDigit())
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Bar chart

/// Income-vs-spending grouped bar chart for the last 6 months. Mirrors the
/// "Earn vs Spent" card on the dashboard but stands on its own here, with a
/// tighter view (no Lent/Owed series — those live on the dashboard).
private struct IncomeVsSpendingChart: View {
    let buckets: [InsightsView.MonthBucket]
    let base: Currency

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(buckets) { b in
                    BarMark(
                        x: .value("Month", b.label),
                        y: .value("Income", b.earned)
                    )
                    .foregroundStyle(Color.green)
                    .position(by: .value("Type", "Income"))
                }
                ForEach(buckets) { b in
                    BarMark(
                        x: .value("Month", b.label),
                        y: .value("Spending", b.spent)
                    )
                    .foregroundStyle(Color.red)
                    .position(by: .value("Type", "Spending"))
                }
            }
            .frame(height: 220)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let n = value.as(Double.self) {
                            Text(shortAxis(n))
                                .font(.caption2)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                legendDot("Income", color: .green)
                legendDot("Spending", color: .red)
                Spacer()
                Text(base.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Compact axis label: "1.2k", "10k", "999" depending on magnitude. Keeps
    /// the chart legible without rotating the labels.
    private func shortAxis(_ n: Double) -> String {
        let abs = Swift.abs(n)
        if abs >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if abs >= 1_000 { return String(format: "%.1fk", n / 1_000) }
        return String(format: "%.0f", n)
    }
}

// MARK: - Pie chart

/// Current-month category breakdown as a donut. Center label shows the largest
/// category's share so a glance answers "what's eating my money?"
private struct CategoryBreakdownPie: View {
    let rows: [(SpendCategory, Double)]
    let base: Currency
    let fx: FXRateStore

    private var total: Double { rows.reduce(0) { $0 + $1.1 } }
    private var top: (SpendCategory, Double)? { rows.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(rows, id: \.0) { (cat, amount) in
                    SectorMark(
                        angle: .value("Amount", amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(cat.color)
                }
            }
            .frame(height: 220)
            .chartLegend(.hidden)
            .overlay {
                if let (cat, amount) = top {
                    VStack(spacing: 2) {
                        Text(cat.rawValue)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(Int((amount / total) * 100))%")
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
            }

            // Legend with amounts — keeps both pieces of info accessible
            // without crowding the donut.
            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { (cat, amount) in
                    HStack {
                        Image(systemName: cat.symbol)
                            .foregroundStyle(cat.color)
                            .frame(width: 22)
                        Text(cat.rawValue).font(.subheadline)
                        Spacer()
                        Text(Formatters.currency(amount, code: base.rawValue))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Biggest spends row

/// Single row in the "Biggest spends this month" list. Shows the category icon,
/// subcategory label, date, and amount (native currency + parenthetical base
/// equivalent when they differ).
private struct BiggestSpendRow: View {
    let row: InsightsView.BigSpend
    let base: Currency
    let fx: FXRateStore

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(row.category.color.opacity(0.18)).frame(width: 32, height: 32)
                Image(systemName: row.category.symbol)
                    .foregroundStyle(row.category.color)
                    .font(.caption.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.subheadline.weight(.semibold))
                Text(Formatters.shortDate(row.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.currency(row.nativeAmount, code: row.nativeCurrency))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.red)
                if row.nativeCurrency != base.rawValue {
                    Text("≈ " + Formatters.currency(row.baseAmount, code: base.rawValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
