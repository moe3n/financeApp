import Foundation
import SwiftData

/// One per calendar month. Used by `NetWorthCalculator` to seed the history
/// chart. We intentionally don't store currency on the snapshot — values are
/// always already converted to the user's base currency at write time, so
/// later base-currency changes just produce a discontinuity we accept.
@Model
final class NetWorthSnapshot {
    var id: UUID = UUID()
    /// First day of the month this snapshot represents (00:00 local).
    var monthStart: Date = Date()
    /// Net worth in the user's base currency at the time of writing.
    var value: Double = 0
    /// When the snapshot was written — used as a tie-breaker for "last entry wins".
    var recordedAt: Date = Date()

    init(monthStart: Date, value: Double, recordedAt: Date = Date()) {
        self.id = UUID()
        self.monthStart = monthStart
        self.value = value
        self.recordedAt = recordedAt
    }
}