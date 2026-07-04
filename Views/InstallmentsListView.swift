import SwiftUI
import SwiftData

struct InstallmentsListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore
    @Query(sort: \Installment.startDate, order: .reverse) private var installments: [Installment]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(installments) { inst in
                    NavigationLink(value: inst) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(inst.title).font(.headline)
                                Spacer()
                                if inst.isFullyPaid {
                                    Text("Paid off")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.green)
                                } else if let d = inst.daysUntilNextDue() {
                                    CountdownPill(days: d)
                                }
                            }
                            HStack {
                                Text(inst.lender.isEmpty ? "No lender" : inst.lender)
                                Spacer()
                                Text(Formatters.currency(inst.monthlyAmount, code: inst.currencyCode) + "/mo")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ProgressView(value: inst.progress)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay { if installments.isEmpty { ContentUnavailableView("No installments", systemImage: "calendar") } }
            .navigationTitle("Installments")
            .navigationDestination(for: Installment.self) { inst in
                InstallmentDetailView(installment: inst)
                    .environmentObject(fx)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingAdd) {
                AddInstallmentView()
                    .environmentObject(fx)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(installments[i]) }
    }
}

/// Compact pill for an installment row showing how soon the next payment is due.
private struct CountdownPill: View {
    let days: Int
    var body: some View {
        let color: Color = {
            if days < 0 || days <= 3 { return .red }
            if days <= 7 { return .orange }
            return .green
        }()
        let label: String = {
            if days < 0 { return "Overdue \(abs(days))d" }
            if days == 0 { return "Due today" }
            if days == 1 { return "Due tomorrow" }
            return "Due in \(days)d"
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct AddInstallmentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateStore

    @State private var title = ""
    @State private var lender = ""
    @State private var principal: Double = 0
    @State private var interest: Double = 0
    @State private var months: Int = 12
    @State private var monthly: Double = 0
    @State private var currency: Currency = .usd
    @State private var startDate = Date()
    @State private var recurrence: Recurrence = .monthlyAnchor
    @State private var recurrenceDay: Int = 1
    @State private var recurrenceWeekday: Int = 2 // default Monday (Calendar iso-style 2)
    @State private var recurrenceIntervalWeeks: Int = 1
    @State private var note = ""

    @State private var titleChips: [String] = ["iPhone BNPL", "MacBook Loan", "Car Loan", "Home Renovation", "Bike EMI"]
    @State private var lenderChips: [String] = ["Bank", "Friend", "Family", "Credit Card", "BNPL"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChipPicker(title: "What is it for?", selection: $title, suggestions: $titleChips)
                    ChipPicker(title: "Lender", selection: $lender, suggestions: $lenderChips)
                }

                Section("Principal & interest") {
                    AmountInput(amount: $principal, currency: $currency, title: "Principal borrowed")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Annual interest").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", interest))
                                .font(.headline.monospacedDigit())
                        }
                        Slider(value: $interest, in: 0...40, step: 0.5) {
                            Text("Interest")
                        }
                        HStack(spacing: 8) {
                            ForEach([0.0, 5.0, 9.5, 14.0, 24.0], id: \.self) { v in
                                Button { interest = v } label: {
                                    Text(v == 0 ? "0%" : String(format: "%.1f%%", v))
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(.thinMaterial, in: Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Term & payment") {
                    Stepper("Term: \(months) months", value: $months, in: 1...360, step: 1)
                        .onChange(of: months) { _, _ in recomputeMonthly() }
                        .onChange(of: principal) { _, _ in recomputeMonthly() }
                        .onChange(of: interest) { _, _ in recomputeMonthly() }
                    if monthly > 0 {
                        AmountInput(amount: $monthly, currency: $currency, title: "Monthly payment")
                    } else {
                        Button {
                            recomputeMonthly()
                        } label: {
                            Label("Calculate monthly payment", systemImage: "function")
                        }
                    }
                }

                Section {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    RecurrencePicker(
                        recurrence: $recurrence,
                        day: $recurrenceDay,
                        weekday: $recurrenceWeekday,
                        intervalWeeks: $recurrenceIntervalWeeks,
                        anchorDate: startDate
                    )
                    if let preview = previewNextDue() {
                        HStack {
                            Image(systemName: preview.icon).foregroundStyle(.orange)
                            Text("Next payment \(Formatters.shortDate(preview.date)) — \(preview.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NoteField(text: $note)
                }
            }
            .navigationTitle("New installment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.isEmpty || monthly <= 0)
                }
            }
        }
    }

    /// Simple amortization formula. Good enough for a quick estimate.
    private func recomputeMonthly() {
        let n = Double(max(months, 1))
        let r = (interest / 100.0) / 12.0
        if r == 0 {
            monthly = principal / n
        } else {
            let pow = Foundation.pow(1 + r, n)
            monthly = principal * (r * pow) / (pow - 1)
        }
    }

    private func previewNextDue() -> (date: Date, label: String, icon: String)? {
        guard monthly > 0, months > 0 else { return nil }
        let cal = Calendar.current
        let preview = Installment(
            recurrence: recurrence,
            recurrenceDay: recurrenceDay,
            recurrenceWeekday: recurrenceWeekday,
            recurrenceIntervalWeeks: recurrenceIntervalWeeks,
            startDate: startDate
        )
        // Approximate the first due date by feeding the helpers a synthetic last-payment anchor:
        // we use the day-before startDate so nextDueDate walks one step forward from startDate.
        guard let first = syntheticFirst(using: preview, calendar: cal) else { return nil }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: first)).day ?? 0
        let label: String
        if days < 0 { label = "\(abs(days))d ago" }
        else if days == 0 { label = "today" }
        else if days == 1 { label = "in 1 day" }
        else { label = "in \(days) days" }
        return (first, label, "calendar.badge.clock")
    }

    /// Builds the first scheduled due date for `preview` by reusing the model's logic.
    /// We can't store it on the model without inserting it, so we mirror the helper locally.
    private func syntheticFirst(using preview: Installment, calendar: Calendar) -> Date? {
        switch preview.recurrence {
        case .monthlyDay:
            var comps = calendar.dateComponents([.year, .month], from: startDate)
            comps.day = max(1, min(28, preview.recurrenceDay))
            return calendar.date(from: comps)
        case .monthlyAnchor:
            var comps = calendar.dateComponents([.year, .month], from: startDate)
            comps.day = max(1, min(28, calendar.component(.day, from: startDate)))
            return calendar.date(from: comps)
        case .weekly:
            return calendar.nextDate(
                after: calendar.date(byAdding: .day, value: -1, to: startDate) ?? startDate,
                matching: DateComponents(weekday: preview.recurrenceWeekday),
                matchingPolicy: .nextTime
            )
        }
    }

    private func save() {
        let inst = Installment(
            title: title, note: note,
            principal: principal, interestRatePercent: interest,
            totalMonths: months, monthlyAmount: monthly,
            currencyCode: currency.rawValue,
            recurrence: recurrence,
            recurrenceDay: recurrenceDay,
            recurrenceWeekday: recurrenceWeekday,
            recurrenceIntervalWeeks: recurrenceIntervalWeeks,
            startDate: startDate, lender: lender
        )
        context.insert(inst)
        try? context.save()
        dismiss()
    }
}

/// Recurrence picker — segmented control for the cadence + content for the selected cadence.
struct RecurrencePicker: View {
    @Binding var recurrence: Recurrence
    @Binding var day: Int
    @Binding var weekday: Int
    @Binding var intervalWeeks: Int
    let anchorDate: Date

    private let weekdaySymbols = Calendar.current.veryShortStandaloneWeekdaySymbols

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recurrence").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            Picker("Recurrence", selection: $recurrence) {
                ForEach(Recurrence.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)

            switch recurrence {
            case .monthlyDay:
                Stepper(value: $day, in: 1...28) {
                    HStack {
                        Text("Day of month")
                        Spacer()
                        Text(ordinal(day)).font(.headline.monospacedDigit())
                    }
                }
            case .monthlyAnchor:
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                    Text("Due on day **\(ordinal(Calendar.current.component(.day, from: anchorDate)))** of every month (start date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .weekly:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { wd in
                            Button {
                                weekday = wd
                            } label: {
                                Text(weekdaySymbols[wd - 1])
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(weekday == wd ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(weekday == wd ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4], id: \.self) { n in
                            Button {
                                intervalWeeks = n
                            } label: {
                                Text(everyNWeeksLabel(n))
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(intervalWeeks == n ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                                    .foregroundStyle(intervalWeeks == n ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func everyNWeeksLabel(_ n: Int) -> String {
        switch n {
        case 1: return "Every week"
        case 2: return "Every 2 weeks"
        case 4: return "Every 4 weeks"
        default: return "Every \(n) weeks"
        }
    }
}

struct InstallmentDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore
    @Bindable var installment: Installment
    @State private var showingAddPayment = false
    @State private var paymentAmount: Double = 0
    @State private var paymentCurrency: Currency = .usd
    @State private var paymentDate = Date()
    @State private var paymentNote = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Lender", value: installment.lender.isEmpty ? "—" : installment.lender)
                LabeledContent("Principal", value: Formatters.currency(installment.principal, code: installment.currencyCode))
                LabeledContent("Interest", value: String(format: "%.2f%%", installment.interestRatePercent))
                LabeledContent("Term", value: "\(installment.totalMonths) months")
                LabeledContent("Monthly", value: Formatters.currency(installment.monthlyAmount, code: installment.currencyCode))
                LabeledContent("Total payable", value: Formatters.currency(installment.totalPayable, code: installment.currencyCode))
                LabeledContent("Paid", value: Formatters.currency(installment.amountPaid, code: installment.currencyCode))
                LabeledContent("Remaining", value: Formatters.currency(installment.amountRemaining, code: installment.currencyCode))
                ProgressView(value: installment.progress)
            }

            Section("Next payment") {
                CountdownCard(
                    nextDate: installment.nextDueDate(),
                    daysUntil: installment.daysUntilNextDue(),
                    currency: installment.currencyCode,
                    monthlyAmount: installment.monthlyAmount,
                    ordinal: installment.nextPaymentOrdinal,
                    totalCount: installment.totalMonths,
                    isPaidOff: installment.isFullyPaid
                )
            }

            Section("Payments") {
                let payments = (installment.payments ?? []).sorted { $0.date > $1.date }
                if payments.isEmpty {
                    Text("No payments yet").foregroundStyle(.secondary)
                } else {
                    ForEach(payments) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(Formatters.shortDate(p.date))
                                if !p.note.isEmpty { Text(p.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(Formatters.currency(p.amount, code: installment.currencyCode))
                        }
                    }
                    .onDelete { idx in
                        let sorted = payments
                        for i in idx { context.delete(sorted[i]) }
                    }
                }
                Button {
                    paymentCurrency = Currency(rawValue: installment.currencyCode) ?? .usd
                    paymentAmount = installment.monthlyAmount
                    paymentDate = Date()
                    showingAddPayment = true
                } label: {
                    Label("Record payment", systemImage: "plus.circle.fill")
                }
            }

            if !installment.note.isEmpty {
                Section("Note") { Text(installment.note) }
            }
        }
        .navigationTitle(installment.title)
        .sheet(isPresented: $showingAddPayment) {
            NavigationStack {
                Form {
                    Section {
                        AmountInput(amount: $paymentAmount, currency: $paymentCurrency, title: "Amount paid")
                            .padding(.vertical, 4)
                        HStack(spacing: 8) {
                            Button { paymentAmount = installment.monthlyAmount } label: {
                                Label("Monthly", systemImage: "calendar")
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            Button { paymentAmount = installment.amountRemaining } label: {
                                Label("Pay off", systemImage: "checkmark.seal")
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                            Button { paymentAmount += installment.monthlyAmount } label: {
                                Label("+1 mo", systemImage: "plus")
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                    }
                    Section {
                        DatePicker("Date", selection: $paymentDate, displayedComponents: .date)
                        NoteField(text: $paymentNote)
                    }
                }
                .navigationTitle("Record payment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddPayment = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if paymentAmount > 0 {
                                let p = InstallmentPayment(amount: paymentAmount, date: paymentDate, note: paymentNote)
                                p.installment = installment
                                if installment.payments == nil { installment.payments = [] }
                                installment.payments?.append(p)
                                context.insert(p)
                                try? context.save()
                            }
                            showingAddPayment = false
                        }
                        .disabled(paymentAmount <= 0)
                    }
                }
            }
        }
    }
}