import Foundation

/// RFC-4180-style CSV serialization for the app's data.
///
/// Each per-model function emits a header row plus one row per record, using
/// comma separators and CRLF line endings. Fields containing commas, quotes,
/// or newlines are wrapped in double quotes with internal quotes doubled.
///
/// `writeAllToTemp(...)` produces four timestamped files in the temporary
/// directory so the user can share the whole dataset in one go via
/// `UIActivityViewController`.
enum CSVExporter {

    // MARK: - Core

    /// Joins a list of rows into a CRLF-terminated CSV string.
    /// Each row is an array of field strings (already escaped by `escape(_:)`).
    static func csv(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n")
            + "\r\n"
    }

    /// Escapes a single field per RFC-4180.
    static func escape(_ field: String) -> String {
        let needs = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        if !needs { return field }
        let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }

    // MARK: - Date formatting

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let isoDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Helpers

    private static func num(_ v: Double) -> String {
        // Two decimals for money-like values; CSV consumers can parse freely.
        String(format: "%.2f", v)
    }

    private static func intOrEmpty(_ v: Int?) -> String {
        guard let v else { return "" }
        return String(v)
    }

    private static func dateOrEmpty(_ d: Date?) -> String {
        guard let d else { return "" }
        return isoDate.string(from: d)
    }

    // MARK: - Earnings

    static func earningsCSV(_ items: [Earning]) -> String {
        var rows: [[String]] = []
        rows.append([
            "id", "date", "source", "category", "amount", "currency", "note"
        ])
        for e in items {
            rows.append([
                e.id.uuidString,
                isoDate.string(from: e.date),
                e.source,
                e.category,
                num(e.amount),
                e.currencyCode,
                e.note
            ])
        }
        return csv(rows)
    }

    // MARK: - Spends

    static func spendsCSV(_ items: [Spend]) -> String {
        var rows: [[String]] = []
        rows.append([
            "id", "date", "category", "amount", "currency", "note"
        ])
        for s in items {
            rows.append([
                s.id.uuidString,
                isoDate.string(from: s.date),
                s.category,
                num(s.amount),
                s.currencyCode,
                s.note
            ])
        }
        return csv(rows)
    }

    // MARK: - Installments

    static func installmentsCSV(_ items: [Installment]) -> String {
        var rows: [[String]] = []
        rows.append([
            "id", "title", "lender", "principal", "interestRatePercent",
            "totalMonths", "monthlyAmount", "currency", "startDate",
            "recurrence", "recurrenceDay", "recurrenceWeekday",
            "recurrenceIntervalWeeks", "paymentsCount", "amountPaid",
            "remainingPrincipal", "isFullyPaid", "note"
        ])
        for i in items {
            let paidList = i.payments ?? []
            let paidCount = paidList.count
            let paidTotal = paidList.reduce(0.0) { $0 + $1.amount }
            let remaining = max(0, i.principal - paidTotal)
            rows.append([
                i.id.uuidString,
                i.title,
                i.lender,
                num(i.principal),
                String(format: "%.4f", i.interestRatePercent),
                String(i.totalMonths),
                num(i.monthlyAmount),
                i.currencyCode,
                isoDate.string(from: i.startDate),
                i.recurrenceRaw,
                String(i.recurrenceDay),
                String(i.recurrenceWeekday),
                String(i.recurrenceIntervalWeeks),
                String(paidCount),
                num(paidTotal),
                num(remaining),
                i.isFullyPaid ? "true" : "false",
                i.note
            ])
        }
        return csv(rows)
    }

    // MARK: - Saving plans

    static func savingsCSV(_ items: [SavingPlan]) -> String {
        var rows: [[String]] = []
        rows.append([
            "id", "name", "targetAmount", "savedAmount", "currency",
            "progress", "monthlyTarget", "deadline", "createdAt", "note"
        ])
        for s in items {
            rows.append([
                s.id.uuidString,
                s.name,
                num(s.targetAmount),
                num(s.savedAmount),
                s.currencyCode,
                String(format: "%.4f", s.progress),
                num(s.monthlyTarget),
                dateOrEmpty(s.deadline),
                isoDateTime.string(from: s.createdAt),
                s.note
            ])
        }
        return csv(rows)
    }

    // MARK: - All → temp files

    /// Writes one CSV per model into the temporary directory.
    /// Files are named `<model>-yyyy-MM-dd.csv` so multiple exports don't clobber.
    @discardableResult
    static func writeAllToTemp(
        earnings: [Earning],
        spends: [Spend],
        installments: [Installment],
        savings: [SavingPlan]
    ) -> [URL] {
        let stamp = isoDate.string(from: Date())
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        var urls: [URL] = []

        let payload: [(String, String)] = [
            ("earnings",     earningsCSV(earnings)),
            ("spends",       spendsCSV(spends)),
            ("installments", installmentsCSV(installments)),
            ("savings",      savingsCSV(savings))
        ]

        for (name, body) in payload {
            let url = dir.appendingPathComponent("financeapp-\(name)-\(stamp).csv")
            do {
                try body.data(using: .utf8)?.write(to: url, options: .atomic)
                urls.append(url)
            } catch {
                // Skip this file; don't abort the whole export.
                continue
            }
        }
        return urls
    }
}