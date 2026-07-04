import Foundation

/// Versioned, Codable snapshot of the entire user-managed store.
///
/// Format: a single JSON file with an envelope (`schema`, `exportedAt`,
/// `appVersion`) and one array per persisted model. Dates are serialised as
/// ISO-8601 strings to keep the file readable + diff-friendly.
///
/// This is the round-trippable companion to `CSVExporter`. The CSV path is
/// for human inspection / Excel; this path is the actual *backup* — the user
/// can import it back to recover after a wipe.
struct BackupPayload: Codable {
    /// Bumped whenever any model field shape changes incompatibly.
    /// `readBackup(from:)` refuses to load files with a newer schema than
    /// the running build understands.
    static let currentSchema = 1

    let schema: Int
    let exportedAt: Date
    let appVersion: String

    var earnings: [EarningRecord]
    var spends: [SpendRecord]
    var installments: [InstallmentRecord]
    var installmentPayments: [InstallmentPaymentRecord]
    var savings: [SavingPlanRecord]
    var budgets: [BudgetRecord]
    var netWorthSnapshots: [NetWorthSnapshotRecord]

    struct EarningRecord: Codable {
        var id: UUID
        var source: String
        var note: String
        var amount: Double
        var currencyCode: String
        var date: Date
        var category: String
    }

    struct SpendRecord: Codable {
        var id: UUID
        var amount: Double
        var currencyCode: String
        var date: Date
        var category: String
        var subcategory: String
        var payee: String
        var note: String
    }

    struct InstallmentRecord: Codable {
        var id: UUID
        var title: String
        var note: String
        var principal: Double
        var interestRatePercent: Double
        var totalMonths: Int
        var monthlyAmount: Double
        var currencyCode: String
        var recurrenceRaw: String
        var recurrenceDay: Int
        var recurrenceWeekday: Int
        var recurrenceIntervalWeeks: Int
        var startDate: Date
        var lender: String
        /// `Installment.id` of every payment in the original order. Resolved
        /// back to `InstallmentPayment` rows in the second pass so the
        /// relationship is consistent after restore.
        var paymentIDs: [UUID]
    }

    struct InstallmentPaymentRecord: Codable {
        var id: UUID
        /// Foreign key to the owning `Installment.id`. Modeled as an optional
        /// UUID so payments can survive a partial restore; we re-link by id.
        var installmentID: UUID
        var amount: Double
        var date: Date
        var note: String
    }

    struct SavingPlanRecord: Codable {
        var id: UUID
        var name: String
        var note: String
        var targetAmount: Double
        var savedAmount: Double
        var currencyCode: String
        var deadline: Date?
        var createdAt: Date
        var monthlyTarget: Double
    }

    struct BudgetRecord: Codable {
        var id: UUID
        var category: String
        var monthlyLimit: Double
        var currencyCode: String
        var note: String
        var createdAt: Date
    }

    struct NetWorthSnapshotRecord: Codable {
        var id: UUID
        var monthStart: Date
        var value: Double
        var recordedAt: Date
    }
}

/// Possible reasons `BackupCodec.readBackup(from:)` failed. The UI surfaces
/// this verbatim in the import alert so the user can self-diagnose.
enum BackupError: LocalizedError {
    case unreadable(underlying: Error)
    case undecodable(underlying: Error)
    case unknownSchema(found: Int, supported: Int)
    case mismatchedInstallmentPaymentCount

    var errorDescription: String? {
        switch self {
        case .unreadable(let e):
            return "Couldn't read backup file: \(e.localizedDescription)"
        case .undecodable(let e):
            return "Backup file is corrupted or in the wrong format: \(e.localizedDescription)"
        case .unknownSchema(let found, let supported):
            return "Backup uses schema \(found) which is newer than this build supports (\(supported)). Update the app and try again."
        case .mismatchedInstallmentPaymentCount:
            return "Backup has inconsistent installment payments. The file may have been edited."
        }
    }
}

/// Encode / decode `BackupPayload` to/from a single JSON file in
/// `FileManager.default.temporaryDirectory`.
enum BackupCodec {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Build an in-memory `BackupPayload` from the user's store. Pure —
    /// doesn't touch the filesystem. Used by `writeBackup(...)`.
    static func makePayload(
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        savings: [SavingPlan],
        budgets: [Budget],
        netWorthSnapshots: [NetWorthSnapshot]
    ) -> BackupPayload {
        // Flatten payments *before* installments so we can preserve the
        // foreign-key shape. Detached from the live context (we still hand
        // them to the coder).
        var paymentRecords: [BackupPayload.InstallmentPaymentRecord] = []
        for inst in installments {
            for p in inst.payments ?? [] {
                paymentRecords.append(.init(
                    id: p.id,
                    installmentID: inst.id,
                    amount: p.amount,
                    date: p.date,
                    note: p.note
                ))
            }
        }
        let installmentRecords = installments.map { inst in
            BackupPayload.InstallmentRecord(
                id: inst.id,
                title: inst.title,
                note: inst.note,
                principal: inst.principal,
                interestRatePercent: inst.interestRatePercent,
                totalMonths: inst.totalMonths,
                monthlyAmount: inst.monthlyAmount,
                currencyCode: inst.currencyCode,
                recurrenceRaw: inst.recurrenceRaw,
                recurrenceDay: inst.recurrenceDay,
                recurrenceWeekday: inst.recurrenceWeekday,
                recurrenceIntervalWeeks: inst.recurrenceIntervalWeeks,
                startDate: inst.startDate,
                lender: inst.lender,
                paymentIDs: (inst.payments ?? []).map { $0.id }
            )
        }
        return BackupPayload(
            schema: BackupPayload.currentSchema,
            exportedAt: Date(),
            appVersion: appVersionString(),
            earnings: earnings.map { e in .init(
                id: e.id, source: e.source, note: e.note, amount: e.amount,
                currencyCode: e.currencyCode, date: e.date, category: e.category) },
            spends: spends.map { s in .init(
                id: s.id, amount: s.amount, currencyCode: s.currencyCode,
                date: s.date, category: s.category, subcategory: s.subcategory,
                payee: s.payee, note: s.note) },
            installments: installmentRecords,
            installmentPayments: paymentRecords,
            savings: savings.map { sv in .init(
                id: sv.id, name: sv.name, note: sv.note,
                targetAmount: sv.targetAmount, savedAmount: sv.savedAmount,
                currencyCode: sv.currencyCode, deadline: sv.deadline,
                createdAt: sv.createdAt, monthlyTarget: sv.monthlyTarget) },
            budgets: budgets.map { b in .init(
                id: b.id, category: b.category, monthlyLimit: b.monthlyLimit,
                currencyCode: b.currencyCode, note: b.note, createdAt: b.createdAt) },
            netWorthSnapshots: netWorthSnapshots.map { n in .init(
                id: n.id, monthStart: n.monthStart, value: n.value,
                recordedAt: n.recordedAt) }
        )
    }

    /// Write the payload as pretty-printed JSON into the temporary directory.
    /// Returns the URL so the caller can hand it to `ShareSheet`.
    @discardableResult
    static func writeBackup(
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        savings: [SavingPlan],
        budgets: [Budget],
        netWorthSnapshots: [NetWorthSnapshot]
    ) throws -> URL {
        let payload = makePayload(
            earnings: earnings, spends: spends, installments: installments,
            savings: savings, budgets: budgets,
            netWorthSnapshots: netWorthSnapshots
        )
        let data = try encoder.encode(payload)
        let stamp = stampString(from: payload.exportedAt)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("financeapp-backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Decode a backup file. Throws `BackupError` for every failure mode so
    /// the UI can show a useful message.
    static func readBackup(from url: URL) throws -> BackupPayload {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.unreadable(underlying: error)
        }
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw BackupError.undecodable(underlying: error)
        }
        guard payload.schema <= BackupPayload.currentSchema else {
            throw BackupError.unknownSchema(
                found: payload.schema,
                supported: BackupPayload.currentSchema
            )
        }
        // Sanity check: every payment id referenced by an installment must
        // exist in the payment list.
        let paymentIDs = Set(payload.installmentPayments.map(\.id))
        for inst in payload.installments {
            for pid in inst.paymentIDs where !paymentIDs.contains(pid) {
                throw BackupError.mismatchedInstallmentPaymentCount
            }
        }
        return payload
    }

    // MARK: - Helpers

    private static func stampString(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private static func appVersionString() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }
}
