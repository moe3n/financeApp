import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore

    @Query(sort: \Earning.date, order: .reverse) private var earnings: [Earning]
    @Query(sort: \SavingPlan.createdAt, order: .reverse) private var savings: [SavingPlan]
    @Query private var installments: [Installment]
    @Query(sort: \Spend.date, order: .reverse) private var spends: [Spend]

    private var calendar: Calendar { Calendar.current }

    private var monthSpends: [Spend] {
        spends.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var spendByCategory: [(SpendCategory, Double)] {
        let grouped = Dictionary(grouping: monthSpends, by: { SpendCategory(rawValue: $0.category) ?? .extra })
        return SpendCategory.allCases.compactMap { c in
            guard let items = grouped[c], !items.isEmpty else { return nil }
            let total = items.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            return (c, total)
        }
    }

    // MARK: - Chart data
    /// Each month for the last 6 calendar months with totals in base currency.
    fileprivate struct MonthBucket: Identifiable {
        let id: Date                 // first day of the month
        let label: String            // "Jan", "Feb"
        let earned: Double
        let spent: Double
        let owed: Double             // installment payment due that month
        let lent: Double             // spends categorized as .lend that month
    }

    private var last6Months: [MonthBucket] {
        let now = Date()
        // Build six month starts, oldest first.
        let months: [Date] = (0..<6).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: calendar.startOfDay(for: now))
        }
        return months.map { monthStart in
            let label = monthLabel(monthStart)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let inMonth: (Date) -> Bool = { calendar.isDate($0, equalTo: monthStart, toGranularity: .month) }

            let earned = earnings
                .filter { inMonth($0.date) }
                .reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            let monthSpendsAll = spends.filter { inMonth($0.date) }
            let spent = monthSpendsAll
                .reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            let lent = monthSpendsAll
                .filter { $0.category == SpendCategory.lend.rawValue }
                .reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            // "Owed" this month: sum of monthlyAmount across active installments
            // that fell due within the month.
            let owed = installments
                .filter { inst in
                    guard !inst.isFullyPaid else { return false }
                    return !inst.dueDates(in: monthStart..<monthEnd, calendar: calendar).isEmpty
                }
                .reduce(0.0) { fx.convertToBase($1.monthlyAmount, from: $1.currencyCode) + $0 }

            return MonthBucket(id: monthStart, label: label, earned: earned, spent: spent, owed: owed, lent: lent)
        }
    }

    private func monthLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: d)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Overview (\(fx.base.rawValue))") {
                    LabeledContent("Total earnings") {
                        Text(Formatters.baseCurrency(totalEarnings, base: fx.base, fx: fx))
                            .font(.headline)
                    }
                    LabeledContent("Spent this month") {
                        Text(Formatters.baseCurrency(totalSpentThisMonth, base: fx.base, fx: fx))
                            .font(.headline).foregroundStyle(.red)
                    }
                    LabeledContent("Total owed") {
                        Text(Formatters.baseCurrency(totalOwed, base: fx.base, fx: fx))
                            .font(.headline).foregroundStyle(.red)
                    }
                    LabeledContent("Total saved") {
                        Text(Formatters.baseCurrency(totalSaved, base: fx.base, fx: fx))
                            .font(.headline).foregroundStyle(.green)
                    }
                    LabeledContent("Net position") {
                        Text(Formatters.baseCurrency(totalEarnings - totalOwed, base: fx.base, fx: fx))
                            .font(.headline)
                    }
                }

                // MARK: Coming up
                Section {
                    ComingUpCard(
                        items: upcomingItems,
                        base: fx.base,
                        fx: fx
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("This week")
                }

                // MARK: Net worth
                Section {
                    NetWorthCard()
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Net worth")
                }

                // MARK: Forecast
                Section {
                    CashFlowForecastView(
                        earnings: earnings,
                        spends: spends,
                        installments: installments.filter { !$0.isFullyPaid }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Forecast")
                }

                // MARK: Budgets
                Section {
                    BudgetProgressCard()
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Budgets")
                }

                // MARK: Charts
                Section("Trends (last 6 months)") {
                    TrendCharts(buckets: last6Months, base: fx.base)
                }

                if !spendByCategory.isEmpty {
                    Section("This month — by category") {
                        ForEach(spendByCategory, id: \.0) { (cat, total) in
                            HStack {
                                Image(systemName: cat.symbol).foregroundStyle(cat.color).frame(width: 24)
                                Text(cat.rawValue)
                                Spacer()
                                Text(Formatters.baseCurrency(total, base: fx.base, fx: fx))
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }

                Section("Active installments") {
                    if installments.isEmpty {
                        Text("No installments yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(installments) { inst in
                            VStack(alignment: .leading) {
                                Text(inst.title).font(.headline)
                                ProgressView(value: inst.progress)
                                HStack {
                                    Text("\(Int(inst.progress * 100))% paid")
                                    Spacer()
                                    Text(Formatters.currency(inst.monthlyAmount, code: inst.currencyCode) + "/mo")
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Saving goals") {
                    if savings.isEmpty {
                        Text("No saving plans yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(savings) { plan in
                            VStack(alignment: .leading) {
                                Text(plan.name).font(.headline)
                                ProgressView(value: plan.progress)
                                HStack {
                                    Text("\(Int(plan.progress * 100))%")
                                    Spacer()
                                    Text(Formatters.currency(plan.savedAmount, code: plan.currencyCode) +
                                         " / " +
                                         Formatters.currency(plan.targetAmount, code: plan.currencyCode))
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Recent spends") {
                    if spends.isEmpty {
                        Text("No spends yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(spends.prefix(5)) { s in
                            let cat = SpendCategory(rawValue: s.category) ?? .extra
                            HStack {
                                Image(systemName: cat.symbol).foregroundStyle(cat.color).frame(width: 22)
                                VStack(alignment: .leading) {
                                    Text(s.subcategory.isEmpty ? cat.rawValue : s.subcategory).font(.headline)
                                    Text(Formatters.shortDate(s.date))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("−" + Formatters.currency(s.amount, code: s.currencyCode))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Recent earnings") {
                    if earnings.isEmpty {
                        Text("No earnings yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(earnings.prefix(5)) { e in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(e.source.isEmpty ? e.category : e.source)
                                    Text(Formatters.shortDate(e.date))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Formatters.currency(e.amount, code: e.currencyCode))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }

    private var totalEarnings: Double {
        earnings.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
    }
    private var totalSpentThisMonth: Double {
        monthSpends.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
    }
    private var totalOwed: Double {
        installments.reduce(0) { fx.convertToBase($1.amountRemaining, from: $1.currencyCode) + $0 }
    }
    private var totalSaved: Double {
        savings.reduce(0) { fx.convertToBase($1.savedAmount, from: $1.currencyCode) + $0 }
    }

    /// Next 7 days of installment due-dates + saving-plan weekly milestones.
    private var upcomingItems: [UpcomingItem] {
        ComingUpBuilder.items(installments: installments, savings: savings)
    }
}

// MARK: - Trend charts
/// Three small Swift Charts for the dashboard:
/// 1. Earn vs Spent — grouped bar (last 6 months, base currency)
/// 2. Lent vs Installment Owed — line chart (last 6 months)
/// 3. A compact donut summarizing the current month's spent vs saved vs owed.
struct TrendCharts: View {
    fileprivate let buckets: [DashboardView.MonthBucket]
    let base: Currency

    private var totalLent: Double { buckets.reduce(0) { $0 + $1.lent } }
    private var totalOwed: Double { buckets.reduce(0) { $0 + $1.owed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1) Earn vs Spent
            chartCard(title: "Earn vs Spent", subtitle: "Last 6 months • \(base.rawValue)") {
                Chart {
                    ForEach(buckets) { b in
                        BarMark(
                            x: .value("Month", b.label),
                            y: .value("Earned", b.earned)
                        )
                        .foregroundStyle(Color.green)
                        .position(by: .value("Type", "Earned"))
                    }
                    ForEach(buckets) { b in
                        BarMark(
                            x: .value("Month", b.label),
                            y: .value("Spent", b.spent)
                        )
                        .foregroundStyle(Color.red)
                        .position(by: .value("Type", "Spent"))
                    }
                }
                .frame(height: 200)
                miniLegend([
                    ("Earned", .green),
                    ("Spent", .red)
                ])
            }

            // 2) Lent vs Installment Owed
            chartCard(title: "Lent vs Owed", subtitle: "Last 6 months • \(base.rawValue)") {
                Chart {
                    ForEach(buckets) { b in
                        LineMark(
                            x: .value("Month", b.label),
                            y: .value("Lent", b.lent)
                        )
                        .foregroundStyle(Color.yellow)
                        .symbol(by: .value("Series", "Lent"))
                        .interpolationMethod(.monotone)
                    }
                    ForEach(buckets) { b in
                        LineMark(
                            x: .value("Month", b.label),
                            y: .value("Owed", b.owed)
                        )
                        .foregroundStyle(Color.red)
                        .symbol(by: .value("Series", "Owed"))
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 200)
                miniLegend([
                    ("Lent", .yellow),
                    ("Owed", .red)
                ])
            }

            // 3) Earn vs Installment Owed summary donut
            chartCard(title: "Earn vs Owed", subtitle: "6-month totals • \(base.rawValue)") {
                let totalEarn = buckets.reduce(0) { $0 + $1.earned }
                let totalOwed = buckets.reduce(0) { $0 + $1.owed }
                let totalSpent = buckets.reduce(0) { $0 + $1.spent }
                Chart {
                    SectorMark(
                        angle: .value("Earn", totalEarn),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.green)
                    SectorMark(
                        angle: .value("Spent", totalSpent),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.red)
                    SectorMark(
                        angle: .value("Owed", totalOwed),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.orange)
                }
                .frame(height: 200)
                .overlay {
                    VStack {
                        Text("Net")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(Formatters.currency(totalEarn - totalOwed - totalSpent, code: base.rawValue))
                            .font(.headline.monospacedDigit())
                    }
                }
                miniLegend([
                    ("Earned", .green),
                    ("Spent", .red),
                    ("Owed", .orange)
                ])
            }
        }
        .padding(.vertical, 4)
    }

    /// Tiny inline legend rendered under each chart since SwiftUI's stock
    /// `chartLegend(position: .bottom)` doesn't always resolve cleanly here.
    private func miniLegend(_ items: [(String, Color)]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.0) { (label, color) in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: helper

    @ViewBuilder
    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Cash flow forecast

struct CashFlowForecastView: View {
    @EnvironmentObject private var fx: FXRateStore
    let earnings: [Earning]
    let spends: [Spend]
    let installments: [Installment]

    var body: some View {
        let summary = CashFlowForecast.summary(
            earnings: earnings, spends: spends, installments: installments, fx: fx
        )
        let points = CashFlowForecast.series(
            earnings: earnings, spends: spends, installments: installments, fx: fx
        )
        // Baseline = 90-day moving average, regardless of active strategy.
        // Cheap to compute (pure math) and gives the user a divergence signal.
        let baseline = CashFlowForecast.series(
            strategy: MovingAverageStrategy(windowDays: 90),
            earnings: earnings, spends: spends, installments: installments, fx: fx
        )
        let showOverlay = CashFlowForecast.activeStrategyKind != .movingAverage90
        CashFlowForecastCard(
            now: Date(), base: fx.base, fx: fx,
            summary: summary, points: points,
            secondaryPoints: showOverlay ? baseline : nil,
            secondaryLabel: ForecastStrategyKind.movingAverage90.displayName
        )
    }
}

// MARK: - Coming up (next 7 days)

/// One scheduled item surfaced on the dashboard.
struct UpcomingItem: Identifiable {
    enum Kind: String { case installment, savingsMilestone }

    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String
    let amount: Double
    let currencyCode: String
    /// Stable color per kind so the timeline reads instantly.
    var color: Color {
        switch kind {
        case .installment:     return .orange
        case .savingsMilestone: return .green
        }
    }
    var icon: String {
        switch kind {
        case .installment:     return "creditcard.fill"
        case .savingsMilestone: return "target"
        }
    }
}

/// Aggregates installment due-dates and saving-plan weekly milestones
/// that fall inside the next 7 days (today + 6 following).
enum ComingUpBuilder {
    static func items(
        now: Date = Date(),
        calendar: Calendar = .current,
        installments: [Installment],
        savings: [SavingPlan]
    ) -> [UpcomingItem] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let endExclusive = calendar.date(byAdding: .day, value: 7, to: startOfToday) else {
            return []
        }
        let range = startOfToday..<endExclusive

        var out: [UpcomingItem] = []

        // Installments — walk every due date in the window for each loan.
        for inst in installments where !inst.isFullyPaid {
            let dates = inst.dueDates(in: range, calendar: calendar)
            for d in dates {
                let daysAway = calendar.dateComponents([.day], from: startOfToday,
                                                        to: calendar.startOfDay(for: d)).day ?? 0
                out.append(UpcomingItem(
                    id: "\(inst.id.uuidString)-\(Int(d.timeIntervalSince1970))",
                    date: d,
                    kind: .installment,
                    title: inst.title.isEmpty ? "Installment" : inst.title,
                    subtitle: dueLabel(daysAway: daysAway, ordinal: inst.nextPaymentOrdinal),
                    amount: inst.monthlyAmount,
                    currencyCode: inst.currencyCode
                ))
            }
        }

        // Savings milestones — every weekly target whose date falls in the window.
        for plan in savings where plan.monthlyTarget > 0 {
            let milestones = plan.weeklyMilestones(now: now, calendar: calendar)
            for m in milestones {
                // Compute the calendar date for this milestone: first day of month + (week-1)*7 days.
                guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { continue }
                guard let milestoneDate = calendar.date(byAdding: .day, value: (m.index - 1) * 7, to: monthStart) else { continue }
                let day = calendar.startOfDay(for: milestoneDate)
                guard day >= startOfToday, day < endExclusive else { continue }
                let daysAway = calendar.dateComponents([.day], from: startOfToday, to: day).day ?? 0
                out.append(UpcomingItem(
                    id: "\(plan.id.uuidString)-\(m.index)-\(Int(milestoneDate.timeIntervalSince1970))",
                    date: milestoneDate,
                    kind: .savingsMilestone,
                    title: plan.name.isEmpty ? "Savings goal" : plan.name,
                    subtitle: "Week \(m.index) — \(dueLabel(daysAway: daysAway, ordinal: m.index))",
                    amount: m.targetAmount,
                    currencyCode: plan.currencyCode
                ))
            }
        }

        return out.sorted { $0.date < $1.date }
    }

    private static func dueLabel(daysAway: Int, ordinal: Int) -> String {
        switch daysAway {
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due in \(daysAway) days"
        }
    }
}

/// Card shown on the Dashboard listing the next 7 days of installments + savings milestones.
struct ComingUpCard: View {
    let items: [UpcomingItem]
    let base: Currency
    let fx: FXRateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Coming up").font(.headline)
                Spacer()
                Text("Next 7 days").font(.caption).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Nothing scheduled in the next week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    TimelineRow(
                        item: item,
                        isLast: idx == items.count - 1,
                        convertedAmount: fx.convertToBase(item.amount, from: item.currencyCode),
                        base: base,
                        fx: fx
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TimelineRow: View {
    let item: UpcomingItem
    let isLast: Bool
    let convertedAmount: Double
    let base: Currency
    let fx: FXRateStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(item.color.opacity(0.18)).frame(width: 28, height: 28)
                    Image(systemName: item.icon).foregroundStyle(item.color).font(.caption.weight(.semibold))
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Formatters.baseCurrency(convertedAmount, base: base, fx: fx))
                        .font(.subheadline.monospacedDigit())
                }
                HStack {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.shortDate(item.date))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, isLast ? 0 : 10)
        }
    }
}