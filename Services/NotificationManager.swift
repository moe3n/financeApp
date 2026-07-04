import Foundation
import SwiftUI
import UserNotifications

/// Owns scheduling of local notifications for upcoming installment due
/// dates and savings-plan deadlines.
///
/// We keep state in UserDefaults so re-launching the app doesn't spam the
/// permission prompt and so the user-visible toggle in Settings persists.
@MainActor
final class NotificationManager: ObservableObject {

    static let leadDaysKey = "FinanceApp.notifications.leadDays"
    static let enabledKey = "FinanceApp.notifications.enabled"
    static let authorizedKey = "FinanceApp.notifications.authorized"

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    @Published var leadDays: Int {
        didSet { defaults.set(leadDays, forKey: Self.leadDaysKey) }
    }

    @Published private(set) var isAuthorized: Bool

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        // Default: enabled, 3 days lead time.
        if d.object(forKey: Self.enabledKey) == nil {
            d.set(true, forKey: Self.enabledKey)
        }
        if d.object(forKey: Self.leadDaysKey) == nil {
            d.set(3, forKey: Self.leadDaysKey)
        }
        self.enabled = d.bool(forKey: Self.enabledKey)
        self.leadDays = max(0, d.integer(forKey: Self.leadDaysKey))
        self.isAuthorized = d.bool(forKey: Self.authorizedKey)
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let granted: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: granted = true
        default: granted = false
        }
        self.isAuthorized = granted
        defaults.set(granted, forKey: Self.authorizedKey)
    }

    /// Requests permission. Returns `true` if the user granted it.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            self.isAuthorized = granted
            defaults.set(granted, forKey: Self.authorizedKey)
            return granted
        } catch {
            self.isAuthorized = false
            defaults.set(false, forKey: Self.authorizedKey)
            return false
        }
    }

    // MARK: - Scheduling

    /// Cancels everything we've previously scheduled and re-schedules based on
    /// the current data set. Safe to call repeatedly.
    func rescheduleAll(installments: [Installment], savings: [SavingPlan]) async {
        guard enabled, isAuthorized else {
            await cancelAll()
            return
        }

        let center = UNUserNotificationCenter.current()
        await cancelAll()

        for inst in installments where !inst.isFullyPaid {
            if let due = inst.nextDueDate() {
                scheduleInstallmentReminder(
                    id: inst.id,
                    title: inst.title,
                    lender: inst.lender,
                    amount: inst.monthlyAmount,
                    currencyCode: inst.currencyCode,
                    dueDate: due,
                    leadDays: leadDays
                )
            }
        }

        for plan in savings {
            if let deadline = plan.deadline, deadline > .now {
                scheduleSavingsDeadline(
                    id: plan.id,
                    name: plan.name,
                    targetAmount: plan.targetAmount,
                    currencyCode: plan.currencyCode,
                    deadline: deadline
                )
            }
        }

        // No-op await to surface any errors to the console.
        _ = try? await center.pendingNotificationRequests()
    }

    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Builders

    private func scheduleInstallmentReminder(
        id: UUID,
        title: String,
        lender: String,
        amount: Double,
        currencyCode: String,
        dueDate: Date,
        leadDays: Int
    ) {
        let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: dueDate) ?? dueDate
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming installment"
        let amountStr = Formatters.currency(amount, code: currencyCode)
        content.body = "\(title) (\(lender.isEmpty ? "Installment" : lender)) — \(amountStr) due \(Formatters.shortDate(dueDate))"
        content.sound = .default
        content.threadIdentifier = "installments"

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: id, kind: "installment"),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleSavingsDeadline(
        id: UUID,
        name: String,
        targetAmount: Double,
        currencyCode: String,
        deadline: Date
    ) {
        let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: deadline) ?? deadline
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Savings deadline"
        let targetStr = Formatters.currency(targetAmount, code: currencyCode)
        content.body = "\(name) — target \(targetStr) by \(Formatters.shortDate(deadline))"
        content.sound = .default
        content.threadIdentifier = "savings"

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: id, kind: "savings"),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func identifier(for id: UUID, kind: String) -> String {
        "financeapp.\(kind).\(id.uuidString)"
    }
}