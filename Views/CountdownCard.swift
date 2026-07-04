import SwiftUI

/// A prominent card showing how soon the next installment is due.
/// Color and tone depend on whether the payment is overdue / today / soon / far.
struct CountdownCard: View {
    let nextDate: Date?
    let daysUntil: Int?
    let currency: String
    let monthlyAmount: Double
    let ordinal: Int
    let totalCount: Int
    let isPaidOff: Bool

    var body: some View {
        HStack(spacing: 16) {
            ring

            VStack(alignment: .leading, spacing: 4) {
                if isPaidOff {
                    Text("Fully paid")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("No upcoming payments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let d = daysUntil, let date = nextDate {
                    Text(headline(for: d))
                        .font(.headline)
                        .foregroundStyle(tone(for: d))
                    Text("Payment \(ordinal) of \(totalCount) • \(Formatters.shortDate(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.currency(monthlyAmount, code: currency))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Text("Schedule unavailable")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(background, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: ringFill)
                .stroke(toneColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if isPaidOff {
                    Image(systemName: "checkmark").font(.headline)
                } else if let d = daysUntil {
                    Text("\(d)").font(.title3.bold().monospacedDigit())
                    Text(d == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "questionmark")
                }
            }
            .foregroundStyle(toneColor)
        }
        .frame(width: 64, height: 64)
    }

    private var ringFill: CGFloat {
        guard let d = daysUntil, !isPaidOff else { return 1 }
        // Map 0...30 days to 0...1 of the ring; clamp wider ranges.
        let frac = Double(max(0, min(30, d))) / 30.0
        return CGFloat(frac)
    }

    // MARK: tone

    private func tone(for days: Int) -> Color {
        if days < 0 { return .red }
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        return .green
    }

    private var toneColor: Color {
        guard !isPaidOff, let d = daysUntil else { return .secondary }
        return tone(for: d)
    }

    private var background: Color {
        toneColor.opacity(0.10)
    }

    private func headline(for d: Int) -> String {
        if d < 0 { return "Overdue by \(abs(d)) day\(abs(d) == 1 ? "" : "s")" }
        if d == 0 { return "Due today" }
        if d == 1 { return "Due tomorrow" }
        return "Due in \(d) days"
    }
}