import Foundation
import SwiftData

/// How an installment recurs over time.
enum Recurrence: String, CaseIterable, Identifiable, Codable {
    /// Recur on the same fixed day-of-month (e.g. the 15th of every month).
    case monthlyDay
    /// Recur on the same day-of-month as the `startDate` (e.g. started on the 17th → 17th of every month).
    case monthlyAnchor
    /// Recur every Nth week on a specific weekday (e.g. every 2nd Tuesday).
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthlyDay:    return "Monthly on a day"
        case .monthlyAnchor: return "Monthly from start"
        case .weekly:        return "Weekly"
        }
    }

    var systemImage: String {
        switch self {
        case .monthlyDay:    return "calendar"
        case .monthlyAnchor: return "calendar.badge.clock"
        case .weekly:        return "calendar.day.timeline.left"
        }
    }
}

/// A loan / EMI / BNPL that you OWE.
@Model
final class Installment {
    var id: UUID = UUID()
    var title: String = ""
    var note: String = ""
    /// Total principal borrowed, in `currencyCode`.
    var principal: Double = 0
    /// Annual interest rate as a percent, e.g. 12.0 for 12%.
    var interestRatePercent: Double = 0
    var totalMonths: Int = 0
    /// Expected monthly payment (principal + interest portion), in `currencyCode`.
    var monthlyAmount: Double = 0
    var currencyCode: String = "USD"

    /// Raw storage for `Recurrence`. SwiftData persists Codable-friendly raw strings cleanly.
    var recurrenceRaw: String = Recurrence.monthlyDay.rawValue
    /// Fixed day-of-month for `.monthlyDay`, or every-Nth-week for `.weekly` (default 1).
    var recurrenceDay: Int = 1
    /// Weekday (1=Sun … 7=Sat, Calendar iso-style with .firstWeekday respected) for `.weekly` and `.biweekly`.
    var recurrenceWeekday: Int = 1
    /// Every-Nth-week interval for `.weekly` (e.g. 2 = every other week).
    var recurrenceIntervalWeeks: Int = 1

    /// Anchor date for the schedule — typically the first disbursement / first due date.
    /// The actual next due date is computed from the recurrence and the last recorded payment.
    var startDate: Date = Date()

    /// Lender name (bank, friend, BNPL provider, etc.).
    var lender: String = ""

    @Relationship(deleteRule: .cascade, inverse: \InstallmentPayment.installment)
    var payments: [InstallmentPayment]? = []

    /// Typed access to the recurrence. Persisted via `recurrenceRaw`.
    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .monthlyDay }
        set { recurrenceRaw = newValue.rawValue }
    }

    /// Derived day-of-month for monthly recurrences. Returns 28-safe clamped value.
    /// Used by legacy view code and the dashboard "owed this month" math.
    var dueDayOfMonth: Int {
        switch recurrence {
        case .monthlyDay:
            return max(1, min(28, recurrenceDay))
        case .monthlyAnchor:
            // Anchor's day-of-month, clamped to 28 so Feb + leap years never miss.
            let day = Calendar.current.component(.day, from: startDate)
            return max(1, min(28, day))
        case .weekly:
            // No day-of-month concept for weekly — return anchor day so legacy callers get *something* stable.
            return max(1, min(28, Calendar.current.component(.day, from: startDate)))
        }
    }

    init(
        title: String = "",
        note: String = "",
        principal: Double = 0,
        interestRatePercent: Double = 0,
        totalMonths: Int = 0,
        monthlyAmount: Double = 0,
        currencyCode: String = "USD",
        recurrence: Recurrence = .monthlyDay,
        recurrenceDay: Int = 1,
        recurrenceWeekday: Int = 1,
        recurrenceIntervalWeeks: Int = 1,
        startDate: Date = Date(),
        lender: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.principal = principal
        self.interestRatePercent = interestRatePercent
        self.totalMonths = totalMonths
        self.monthlyAmount = monthlyAmount
        self.currencyCode = currencyCode
        self.recurrenceRaw = recurrence.rawValue
        self.recurrenceDay = max(1, min(28, recurrenceDay))
        self.recurrenceWeekday = max(1, min(7, recurrenceWeekday))
        self.recurrenceIntervalWeeks = max(1, min(52, recurrenceIntervalWeeks))
        self.startDate = startDate
        self.lender = lender
    }

    // MARK: - Schedule helpers

    var totalPayable: Double {
        monthlyAmount * Double(totalMonths)
    }

    var amountPaid: Double {
        (payments ?? []).reduce(0) { $0 + $1.amount }
    }

    var amountRemaining: Double {
        max(totalPayable - amountPaid, 0)
    }

    var progress: Double {
        guard totalPayable > 0 else { return 0 }
        return min(amountPaid / totalPayable, 1)
    }

    /// Number of payments already recorded, clamped by `totalMonths`.
    var paymentsMadeCount: Int {
        let n = (payments ?? []).count
        return min(n, totalMonths)
    }

    /// The ordinal of the NEXT scheduled payment, e.g. "Payment 7 of 12".
    var nextPaymentOrdinal: Int {
        min(paymentsMadeCount + 1, totalMonths)
    }

    /// Whether everything has been paid off.
    var isFullyPaid: Bool {
        paymentsMadeCount >= totalMonths || amountRemaining <= 0
    }

    /// Computes the next due date based on the last recorded payment (or `startDate`)
    /// and the chosen `Recurrence`. Returns nil if the loan is fully paid off.
    func nextDueDate(calendar: Calendar = .current) -> Date? {
        guard !isFullyPaid else { return nil }

        let sorted = (payments ?? []).map { $0.date }.sorted()
        // Anchor = max(startDate, last payment date). If no payment, use startDate.
        let lastDate: Date = sorted.last ?? startDate

        switch recurrence {
        case .monthlyDay:
            // Same day-of-month as the chosen fixed day, in the NEXT month after lastDate.
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: lastDate) else { return nil }
            var comps = calendar.dateComponents([.year, .month], from: nextMonth)
            comps.day = max(1, min(28, recurrenceDay))
            return calendar.date(from: comps)

        case .monthlyAnchor:
            // Same day-of-month as the startDate anchor, in the NEXT month after lastDate.
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: lastDate) else { return nil }
            var comps = calendar.dateComponents([.year, .month], from: nextMonth)
            comps.day = max(1, min(28, Calendar.current.component(.day, from: startDate)))
            return calendar.date(from: comps)

        case .weekly:
            // Every recurrenceIntervalWeeks-th occurrence of recurrenceWeekday after lastDate.
            return nextWeeklyDate(after: lastDate, calendar: calendar)
        }
    }

    /// Walks forward from `after` to the next weekly occurrence honoring `recurrenceIntervalWeeks` and `recurrenceWeekday`.
    /// If the same weekday falls on/before today, advance at least one step to the next valid instance.
    private func nextWeeklyDate(after lastDate: Date, calendar: Calendar) -> Date? {
        let weekday = max(1, min(7, recurrenceWeekday))
        let intervalWeeks = max(1, recurrenceIntervalWeeks)
        // First occurrence on/after lastDate.
        guard var candidate = calendar.nextDate(
            after: lastDate,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
        ) else { return nil }

        // Walk forward by intervalWeeks weeks at a time until strictly in the future.
        // (first candidate is >= lastDate, but we want strictly > lastDate so payments don't double-fire.)
        var safety = 0
        while candidate <= lastDate && safety < 1000 {
            guard let next = calendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: candidate) else { return nil }
            candidate = next
            safety += 1
        }
        return candidate
    }

    /// Whole-day countdown to the next payment. Negative if overdue.
    func daysUntilNextDue(calendar: Calendar = .current) -> Int? {
        guard let next = nextDueDate(calendar: calendar) else { return nil }
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfNext  = calendar.startOfDay(for: next)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfNext).day
    }

    /// Returns every scheduled due date that falls inside the half-open range `range`.
    /// Used by the dashboard to compute "owed this month" without walking month-by-month.
    func dueDates(in range: Range<Date>, calendar: Calendar = .current) -> [Date] {
        guard !isFullyPaid, totalMonths > 0 else { return [] }

        switch recurrence {
        case .monthlyDay, .monthlyAnchor:
            return monthlyDueDates(in: range, calendar: calendar)
        case .weekly:
            return weeklyDueDates(in: range, calendar: calendar)
        }
    }

    private func monthlyDueDates(in range: Range<Date>, calendar: Calendar) -> [Date] {
        let earliest = max(calendar.startOfDay(for: range.lowerBound), calendar.startOfDay(for: startDate))
        var cursorComps = calendar.dateComponents([.year, .month], from: earliest)
        cursorComps.day = max(1, min(28, dueDayOfMonth))
        guard var cursor = calendar.date(from: cursorComps) else { return [] }
        var out: [Date] = []
        var remaining = totalMonths - paymentsMadeCount
        while cursor < range.upperBound, remaining > 0 {
            let day = calendar.startOfDay(for: cursor)
            if day >= range.lowerBound { out.append(day) }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = nextMonth
            remaining -= 1
        }
        return out
    }

    private func weeklyDueDates(in range: Range<Date>, calendar: Calendar) -> [Date] {
        let intervalWeeks = max(1, recurrenceIntervalWeeks)
        let weekday = max(1, min(7, recurrenceWeekday))
        // Walk forward in N-week jumps from `startDate` until past range.upperBound.
        var out: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        var remaining = totalMonths - paymentsMadeCount // for weekly we still use this as a coarse cap
        // Align cursor's weekday to the chosen one, advancing to the first instance >= startDate.
        if let aligned = calendar.nextDate(
            after: calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
        ) {
            cursor = aligned
        }
        var safety = 0
        while cursor < range.upperBound, remaining > 0, safety < 10000 {
            if cursor >= range.lowerBound { out.append(cursor) }
            guard let next = calendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: cursor) else { break }
            cursor = next
            remaining -= 1
            safety += 1
        }
        return out
    }
}

@Model
final class InstallmentPayment {
    var id: UUID = UUID()
    var installment: Installment?
    var amount: Double = 0
    var date: Date = Date()
    var note: String = ""

    init(amount: Double = 0, date: Date = Date(), note: String = "") {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.note = note
    }
}