import Foundation
import SwiftData

@Model
final class SavingPlan {
    var id: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var targetAmount: Double = 0
    var savedAmount: Double = 0
    var currencyCode: String = "USD"
    /// Optional target date.
    var deadline: Date? = nil
    var createdAt: Date = Date()

    /// How much you want to save per calendar month. 0 disables the monthly
    /// milestone UI. Weekly milestones are derived as monthlyTarget / 4.
    var monthlyTarget: Double = 0

    init(
        name: String = "",
        note: String = "",
        targetAmount: Double = 0,
        savedAmount: Double = 0,
        currencyCode: String = "USD",
        deadline: Date? = nil,
        createdAt: Date = Date(),
        monthlyTarget: Double = 0
    ) {
        self.id = UUID()
        self.name = name
        self.note = note
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.currencyCode = currencyCode
        self.deadline = deadline
        self.createdAt = createdAt
        self.monthlyTarget = max(0, monthlyTarget)
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(savedAmount / targetAmount, 1)
    }

    // MARK: - Weekly milestones
    //
    // We split the month evenly into 4 weekly checkpoints so the user always
    // sees 4 dots. Each milestone's target is monthlyTarget * (weekIndex / 4),
    // and it's "achieved" when savedAmount (since the start of the same
    // calendar month) is at least that much.
    //
    // For plans older than one month we clamp to the most recent calendar
    // month so the dots always represent "this month so far".

    /// Returns the four weekly milestones for the current calendar month,
    /// measured against savings accumulated in the same month.
    /// Each milestone exposes: index (1...4), targetAmount, isAchieved,
    /// weekLabel ("Week 1", etc.), and color tier for the UI.
    func weeklyMilestones(
        now: Date = Date(),
        calendar: Calendar = .current,
        earnings: [Double] = []
    ) -> [WeeklyMilestone] {
        guard monthlyTarget > 0 else { return [] }

        // Savings so far this calendar month: either derived from a contributions
        // list (if you wire one in) or approximated as `min(savedAmount,
        // monthlyTarget)` so the dots always feel responsive. We use the latter
        // to keep this model self-contained.
        let savedThisMonth = min(savedAmount, monthlyTarget)
        let perWeek = monthlyTarget / 4.0

        // "Week in month" 1...4 from today's day-of-month.
        let day = calendar.component(.day, from: now)
        let ordinal = max(1, min(4, Int(ceil(Double(day) / 7.0))))

        return (1...4).map { week in
            let targetForWeek = perWeek * Double(week)
            return WeeklyMilestone(
                index: week,
                targetAmount: targetForWeek,
                isAchieved: savedThisMonth + 0.0001 >= targetForWeek,
                isCurrent: week == ordinal,
                weekLabel: "Week \(week)"
            )
        }
    }

    /// "Ahead of pace" / "on pace" / "behind pace" relative to `monthlyTarget`
    /// for the current calendar month, based on elapsed days.
    enum PaceStatus { case ahead, onTrack, behind, noTarget }

    func monthlyPace(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (status: PaceStatus, expected: Double, actual: Double) {
        guard monthlyTarget > 0 else {
            return (.noTarget, 0, savedAmount)
        }
        // Days in *this* month and days elapsed so far.
        let interval = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)
        let totalSeconds = interval.duration
        let elapsed = max(0, now.timeIntervalSince(interval.start))
        let fraction = totalSeconds > 0 ? min(elapsed / totalSeconds, 1) : 1
        let expected = monthlyTarget * fraction

        // Use up to monthlyTarget of the saved amount as "this-month" savings.
        let actual = min(savedAmount, monthlyTarget)

        let status: PaceStatus
        if actual >= expected * 1.05 { status = .ahead }
        else if actual >= expected * 0.9 { status = .onTrack }
        else { status = .behind }
        return (status, expected, actual)
    }
}

/// Computed per-week checkpoint in the savings plan. Not persisted — derived
/// from `SavingPlan` state.
struct WeeklyMilestone: Identifiable {
    let index: Int        // 1...4
    let targetAmount: Double
    let isAchieved: Bool
    let isCurrent: Bool   // the week the user is currently in
    let weekLabel: String

    var id: Int { index }
}