import Foundation
import SwiftData

/// Applies a `BackupPayload` to a `ModelContext` by atomically wiping the
/// existing store and re-inserting every model.
///
/// The wipe-and-insert strategy is intentional: a backup is meant to be the
/// ground truth, and partial merges on UUID collisions cause gnarly duplicates
/// (the same `Earning` showing up twice because the user already had one with
/// the same `id`). The trade-off is that the user must explicitly confirm
/// before `applyBackup` runs — handled in the Settings view.
///
/// All access is on the main actor so the SwiftData context stays safe.
@MainActor
enum BackupStore {

    /// Replace everything in `context` with `payload`. Throws if any step
    /// fails so the caller can surface an alert rather than silently leaving
    /// the store half-mutated.
    static func applyBackup(_ payload: BackupPayload, to context: ModelContext) throws {
        try wipe(context)
        try insert(payload, into: context)
        try context.save()
    }

    // MARK: - Wipe

    private static func wipe(_ context: ModelContext) throws {
        try context.delete(model: NetWorthSnapshot.self)
        try context.delete(model: Budget.self)
        try context.delete(model: SavingPlan.self)
        try context.delete(model: InstallmentPayment.self)
        try context.delete(model: Installment.self)
        try context.delete(model: Spend.self)
        try context.delete(model: Earning.self)
        try context.save()
    }

    // MARK: - Insert

    private static func insert(_ payload: BackupPayload, into context: ModelContext) throws {
        // Earnings
        for r in payload.earnings {
            context.insert(Earning(
                source: r.source, note: r.note, amount: r.amount,
                currencyCode: r.currencyCode, date: r.date,
                category: r.category
            ))
        }
        // Spends
        for r in payload.spends {
            context.insert(Spend(
                amount: r.amount, currencyCode: r.currencyCode,
                date: r.date, category: r.category, subcategory: r.subcategory,
                payee: r.payee, note: r.note
            ))
        }
        // Installments first; payments require their owner to exist.
        let installmentByID: [UUID: Installment] = try payload.installments.reduce(into: [:]) { acc, r in
            let inst = Installment(
                title: r.title, note: r.note, principal: r.principal,
                interestRatePercent: r.interestRatePercent,
                totalMonths: r.totalMonths, monthlyAmount: r.monthlyAmount,
                currencyCode: r.currencyCode,
                recurrence: Recurrence(rawValue: r.recurrenceRaw) ?? .monthlyDay,
                recurrenceDay: r.recurrenceDay,
                recurrenceWeekday: r.recurrenceWeekday,
                recurrenceIntervalWeeks: r.recurrenceIntervalWeeks,
                startDate: r.startDate, lender: r.lender
            )
            context.insert(inst)
            acc[r.id] = inst
        }
        // Payments linked to their installment.
        for r in payload.installmentPayments {
            let payment = InstallmentPayment(
                amount: r.amount, date: r.date, note: r.note
            )
            payment.installment = installmentByID[r.installmentID]
            context.insert(payment)
        }
        // Saving plans
        for r in payload.savings {
            context.insert(SavingPlan(
                name: r.name, note: r.note,
                targetAmount: r.targetAmount, savedAmount: r.savedAmount,
                currencyCode: r.currencyCode, deadline: r.deadline,
                createdAt: r.createdAt, monthlyTarget: r.monthlyTarget
            ))
        }
        // Budgets
        for r in payload.budgets {
            context.insert(Budget(
                category: r.category, monthlyLimit: r.monthlyLimit,
                currencyCode: r.currencyCode, note: r.note,
                createdAt: r.createdAt
            ))
        }
        // Net worth snapshots
        for r in payload.netWorthSnapshots {
            context.insert(NetWorthSnapshot(
                monthStart: r.monthStart, value: r.value,
                recordedAt: r.recordedAt
            ))
        }
    }
}
