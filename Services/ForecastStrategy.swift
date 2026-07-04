import Foundation

/// Pluggable forecast algorithm. The dashboard forecast card delegates to
/// whichever strategy is configured, so swapping in a smarter (e.g.
/// ML-trained, day-of-week weighted) implementation is a one-line change.
///
/// All implementations are `@MainActor` because the underlying FX store is
/// `@MainActor`-isolated.
@MainActor
protocol ForecastStrategy {
    /// Produce a forecast for the next `days` days starting at `now`.
    /// Implementations should use `fx.convertToBase(_:from:)` for FX conversion.
    func project(
        now: Date,
        days: Int,
        calendar: Calendar,
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        fx: FXRateStore
    ) -> CashFlowForecast.Summary

    /// Distinct human label so the UI can show which strategy produced the
    /// forecast. Defaults to the type name.
    var displayName: String { get }
}

extension ForecastStrategy where Self == MovingAverageStrategy {
    static var movingAverage: MovingAverageStrategy { .init() }
}

// MARK: - Moving-average (default)

/// The original forecast logic: smooth daily drip at the average rate of the
/// last 90 days, with installment payments landing on their actual
/// `dueDates`. This is intentionally simple — it's the baseline we compare
/// future strategies against.
struct MovingAverageStrategy: ForecastStrategy {
    let windowDays: Int

    init(windowDays: Int = 90) {
        self.windowDays = windowDays
    }

    var displayName: String { "Moving average (last \(windowDays) days)" }

    func project(
        now: Date,
        days: Int,
        calendar: Calendar,
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        fx: FXRateStore
    ) -> CashFlowForecast.Summary {
        let start = ForecastMath.historicalNetBalance(
            earnings: earnings, spends: spends, installments: installments, fx: fx
        )
        let income = ForecastMath.projectedIncome(
            now: now, days: days, calendar: calendar, earnings: earnings,
            windowDays: windowDays, fx: fx
        )
        let spending = ForecastMath.projectedSpending(
            now: now, days: days, calendar: calendar, spends: spends,
            windowDays: windowDays, fx: fx
        )
        let installmentTotal = ForecastMath.projectedInstallments(
            now: now, days: days, calendar: calendar, installments: installments,
            fx: fx
        )
        return CashFlowForecast.Summary(
            startBalance: start,
            projectedIncome: income,
            projectedSpending: spending,
            projectedInstallments: installmentTotal,
            endBalance: start + income - spending - installmentTotal
        )
    }
}

// MARK: - Shared math (used by strategies)

/// Stateless helpers that any strategy can reuse. Kept separate from
/// `CashFlowForecast` so the strategy implementation is the only thing that
/// decides *how* to compute a summary.
@MainActor
enum ForecastMath {

    static func historicalNetBalance(
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        fx: FXRateStore
    ) -> Double {
        let earningsBase = earnings.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
        let spendsBase   = spends.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
        let installmentPaymentsBase = installments.reduce(0) { acc, inst in
            (inst.payments ?? []).reduce(acc) { $0 + fx.convertToBase($1.amount, from: inst.currencyCode) }
        }
        return earningsBase - spendsBase - installmentPaymentsBase
    }

    static func projectedIncome(
        now: Date,
        days: Int,
        calendar: Calendar,
        earnings: [Earning],
        windowDays: Int,
        fx: FXRateStore
    ) -> Double {
        guard let rate = dailyRate(now: now, calendar: calendar, items: earnings,
                                   windowDays: windowDays, fx: fx) else { return 0 }
        return rate * Double(days)
    }

    static func projectedSpending(
        now: Date,
        days: Int,
        calendar: Calendar,
        spends: [Spend],
        windowDays: Int,
        fx: FXRateStore
    ) -> Double {
        guard let rate = dailyRate(now: now, calendar: calendar, items: spends,
                                   windowDays: windowDays, fx: fx) else { return 0 }
        return rate * Double(days)
    }

    static func projectedInstallments(
        now: Date,
        days: Int,
        calendar: Calendar,
        installments: [Installment],
        fx: FXRateStore
    ) -> Double {
        guard let startOfToday = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let endExclusive = calendar.date(byAdding: .day, value: days, to: startOfToday) else { return 0 }
        var total = 0.0
        for inst in installments where !inst.isFullyPaid {
            let dates = inst.dueDates(in: startOfToday..<endExclusive, calendar: calendar)
            for _ in dates {
                total += fx.convertToBase(inst.monthlyAmount, from: inst.currencyCode)
            }
        }
        return total
    }

    /// Daily rate = (sum of items in last `windowDays` days) / `windowDays`.
    /// Falls back to (all-time total / 30) when there's no recent history.
    static func dailyRate<T: HasAmount>(
        now: Date,
        calendar: Calendar,
        items: [T],
        windowDays: Int,
        fx: FXRateStore
    ) -> Double? {
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) else { return nil }
        let recent = items.filter { $0.date >= cutoff }
        let totalInBase: Double
        if recent.isEmpty {
            totalInBase = items.reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
            return totalInBase / 30.0
        }
        totalInBase = recent.reduce(0.0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
        return totalInBase / Double(windowDays)
    }
}

/// Lightweight protocol used by `ForecastMath` so earnings and spends can
/// share the same `dailyRate` function.
protocol HasAmount {
    var amount: Double { get }
    var currencyCode: String { get }
    var date: Date { get }
}

extension Earning: HasAmount {}
extension Spend: HasAmount {}

// MARK: - Strategy catalog

/// Stable, user-facing identifiers for built-in forecast strategies. The raw
/// value is what's persisted in `@AppStorage`, so it's intentionally a string
/// and adding new cases is a non-breaking change.
enum ForecastStrategyKind: String, CaseIterable, Identifiable {
    case movingAverage90 = "movingAverage.90"
    case movingAverage30 = "movingAverage.30"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movingAverage90: return "Moving average (90 days)"
        case .movingAverage30: return "Moving average (30 days)"
        }
    }

    var shortLabel: String {
        switch self {
        case .movingAverage90: return "MA-90"
        case .movingAverage30: return "MA-30"
        }
    }
}

/// Factory + active-strategy plumbing. Lives next to the protocol so adding a
/// strategy means: implement it, add a case to `ForecastStrategyKind`, and add
/// a branch in `ForecastStrategyCatalog.make(_:)`. Nothing in the view layer
/// changes.
@MainActor
enum ForecastStrategyCatalog {
    static let defaultKind: ForecastStrategyKind = .movingAverage90

    static func make(_ kind: ForecastStrategyKind) -> any ForecastStrategy {
        switch kind {
        case .movingAverage90: return MovingAverageStrategy(windowDays: 90)
        case .movingAverage30: return MovingAverageStrategy(windowDays: 30)
        }
    }
}

extension CashFlowForecast {
    /// Active strategy kind — backed by `@AppStorage` so it survives launches.
    /// Read this from the view layer instead of holding your own copy.
    @MainActor
    static var activeStrategyKind: ForecastStrategyKind {
        let raw = UserDefaults.standard.string(forKey: Keys.activeStrategyKind)
            ?? ForecastStrategyCatalog.defaultKind.rawValue
        return ForecastStrategyKind(rawValue: raw)
            ?? ForecastStrategyCatalog.defaultKind
    }

    @MainActor
    static func setStrategy(_ kind: ForecastStrategyKind) {
        UserDefaults.standard.set(kind.rawValue, forKey: Keys.activeStrategyKind)
        setStrategy(ForecastStrategyCatalog.make(kind))
    }

    private enum Keys {
        static let activeStrategyKind = "FinanceApp.forecast.strategy.kind"
    }
}