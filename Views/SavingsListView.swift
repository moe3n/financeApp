import SwiftUI
import SwiftData

struct SavingsListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore
    @Query(sort: \SavingPlan.createdAt, order: .reverse) private var plans: [SavingPlan]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    NavigationLink(value: plan) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(plan.name).font(.headline)
                                Spacer()
                                if plan.monthlyTarget > 0 {
                                    PaceBadge(status: plan.monthlyPace().status)
                                }
                            }
                            ProgressView(value: plan.progress)
                            HStack {
                                Text("\(Int(plan.progress * 100))%")
                                Spacer()
                                Text(Formatters.currency(plan.savedAmount, code: plan.currencyCode) +
                                     " / " +
                                     Formatters.currency(plan.targetAmount, code: plan.currencyCode))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if plan.monthlyTarget > 0 {
                                WeeklyDotsRow(milestones: plan.weeklyMilestones(), currency: plan.currencyCode)
                            }
                            if let d = plan.deadline {
                                Text("By \(Formatters.shortDate(d))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay { if plans.isEmpty { ContentUnavailableView("No saving plans", systemImage: "target") } }
            .navigationTitle("Savings")
            .navigationDestination(for: SavingPlan.self) { plan in
                SavingPlanDetailView(plan: plan).environmentObject(fx)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingAdd) {
                AddSavingPlanView().environmentObject(fx)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(plans[i]) }
    }
}

/// Compact "ahead / on track / behind" pill used in the savings list rows.
private struct PaceBadge: View {
    let status: SavingPlan.PaceStatus
    var body: some View {
        let (label, color): (String, Color) = {
            switch status {
            case .ahead:    return ("Ahead", .green)
            case .onTrack:  return ("On track", .blue)
            case .behind:   return ("Behind", .orange)
            case .noTarget: return ("", .secondary)
            }
        }()
        if status == .noTarget { EmptyView() } else {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
    }
}

/// Four small dots showing weekly milestones. The current week is highlighted
/// with a ring; achieved weeks are filled with the plan color.
struct WeeklyDotsRow: View {
    let milestones: [WeeklyMilestone]
    let currency: String

    var body: some View {
        if milestones.isEmpty { EmptyView() } else {
            HStack(spacing: 10) {
                ForEach(milestones) { m in
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(m.isCurrent ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: m.isCurrent ? 2 : 1)
                                .frame(width: 14, height: 14)
                            if m.isAchieved {
                                Circle().fill(Color.green).frame(width: 10, height: 10)
                            } else if m.isCurrent {
                                Circle().fill(Color.accentColor.opacity(0.4)).frame(width: 10, height: 10)
                            }
                        }
                        Text(m.weekLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let last = milestones.last {
                    Text(Formatters.currency(last.targetAmount, code: currency))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AddSavingPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateStore

    @State private var name = ""
    @State private var note = ""
    @State private var target: Double = 0
    @State private var saved: Double = 0
    @State private var monthly: Double = 0
    @State private var currency: Currency = .usd
    @State private var hasDeadline = false
    @State private var deadline = Date()

    @State private var nameChips: [String] = [
        "Emergency fund", "Vacation", "New laptop", "Down payment",
        "Wedding", "Gift fund", "Bike", "Holiday"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChipPicker(title: "Goal", selection: $name, suggestions: $nameChips)
                }
                Section("Target") {
                    AmountInput(amount: $target, currency: $currency, title: "Total target")
                    AmountInput(amount: $saved, currency: $currency, title: "Already saved")
                    AmountInput(amount: $monthly, currency: $currency, title: "Save per month (optional)")
                    if monthly > 0 {
                        HStack(spacing: 8) {
                            weeklyChip(50)
                            weeklyChip(25)
                            weeklyChip(10)
                        }
                        Text("≈ \(Formatters.currency(monthly / 4, code: currency.rawValue)) per week to stay on track")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    }
                    NoteField(text: $note)
                }
            }
            .navigationTitle("New saving plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || target <= 0)
                }
            }
        }
    }

    private func weeklyChip(_ percent: Int) -> some View {
        let v = monthly * Double(percent) / 100.0
        return Button { monthly = v } label: {
            Text("\(percent)% of monthly")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private func save() {
        let p = SavingPlan(
            name: name, note: note,
            targetAmount: target, savedAmount: saved,
            currencyCode: currency.rawValue,
            deadline: hasDeadline ? deadline : nil,
            monthlyTarget: monthly
        )
        context.insert(p)
        try? context.save()
        dismiss()
    }
}

struct SavingPlanDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore
    @Bindable var plan: SavingPlan
    @State private var contribution: Double = 0
    @State private var contributionCurrency: Currency = .usd

    var body: some View {
        Form {
            Section {
                LabeledContent("Target", value: Formatters.currency(plan.targetAmount, code: plan.currencyCode))
                LabeledContent("Saved", value: Formatters.currency(plan.savedAmount, code: plan.currencyCode))
                if let d = plan.deadline {
                    LabeledContent("Deadline", value: Formatters.shortDate(d))
                }
                ProgressView(value: plan.progress)
            }

            // Phase 2 — monthly target + weekly milestones card
            if plan.monthlyTarget > 0 {
                Section("This month's plan") {
                    MonthlyMilestoneCard(plan: plan)
                }
            }

            Section("Add contribution") {
                AmountInput(amount: $contribution, currency: $contributionCurrency, title: "Amount")
                    .padding(.vertical, 4)
                HStack(spacing: 8) {
                    quickChip(50)
                    quickChip(100)
                    quickChip(500)
                    quickChip(1000)
                    Button { add(plan.targetAmount - plan.savedAmount) } label: {
                        Label("Finish", systemImage: "flag.checkered")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    .disabled(plan.progress >= 1)
                }
                Button("Add to savings") { add(contribution) }
                    .disabled(contribution <= 0)
            }

            if !plan.note.isEmpty {
                Section("Note") { Text(plan.note) }
            }
        }
        .navigationTitle(plan.name)
        .onAppear { contributionCurrency = Currency(rawValue: plan.currencyCode) ?? .usd }
    }

    private func quickChip(_ v: Double) -> some View {
        Button { contribution = v } label: {
            Text("+\(Formatters.currency(v, code: contributionCurrency.rawValue))")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private func add(_ amount: Double) {
        guard amount > 0 else { return }
        plan.savedAmount += amount
        try? context.save()
        contribution = 0
    }
}

/// Card on the saving plan detail view showing the four weekly milestones
/// plus an "ahead / on track / behind" pace indicator for the current month.
struct MonthlyMilestoneCard: View {
    let plan: SavingPlan

    var body: some View {
        let milestones = plan.weeklyMilestones()
        let pace = plan.monthlyPace()

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly target")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.currency(plan.monthlyTarget, code: plan.currencyCode))
                        .font(.title3.bold().monospacedDigit())
                }
                Spacer()
                PaceIndicator(status: pace.status)
            }

            // 4-week progress: a horizontal bar split into 4 segments, filled per milestone.
            WeeklyProgressBar(milestones: milestones)

            HStack {
                ForEach(milestones) { m in
                    VStack(spacing: 2) {
                        Text(m.weekLabel).font(.caption2.weight(.semibold))
                            .foregroundStyle(m.isCurrent ? Color.accentColor : .secondary)
                        Text(Formatters.currency(m.targetAmount, code: plan.currencyCode))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Pace detail
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: paceIcon(pace.status))
                    .foregroundStyle(paceColor(pace.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(paceHeadline(pace.status)).font(.subheadline.weight(.semibold))
                    Text(paceSubtitle(pace))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(paceColor(pace.status).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.vertical, 4)
    }

    private func paceIcon(_ s: SavingPlan.PaceStatus) -> String {
        switch s {
        case .ahead:    return "arrow.up.right.circle.fill"
        case .onTrack:  return "checkmark.circle.fill"
        case .behind:   return "arrow.down.right.circle.fill"
        case .noTarget: return "circle"
        }
    }
    private func paceColor(_ s: SavingPlan.PaceStatus) -> Color {
        switch s {
        case .ahead:    return .green
        case .onTrack:  return .blue
        case .behind:   return .orange
        case .noTarget: return .secondary
        }
    }
    private func paceHeadline(_ s: SavingPlan.PaceStatus) -> String {
        switch s {
        case .ahead:    return "Ahead of pace"
        case .onTrack:  return "On track"
        case .behind:   return "Behind this month"
        case .noTarget: return "No monthly target set"
        }
    }
    private func paceSubtitle(_ pace: (status: SavingPlan.PaceStatus, expected: Double, actual: Double)) -> String {
        if pace.status == .noTarget { return "" }
        let diff = pace.actual - pace.expected
        let prefix = diff >= 0 ? "+" : "−"
        let absDiff = Formatters.currency(abs(diff), code: plan.currencyCode)
        return "Expected \(Formatters.currency(pace.expected, code: plan.currencyCode)) so far • \(prefix)\(absDiff)"
    }
}

private struct PaceIndicator: View {
    let status: SavingPlan.PaceStatus
    var body: some View {
        let (text, color): (String, Color) = {
            switch status {
            case .ahead:    return ("Ahead", .green)
            case .onTrack:  return ("On track", .blue)
            case .behind:   return ("Behind", .orange)
            case .noTarget: return ("", .secondary)
            }
        }()
        Group {
            if status != .noTarget {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }
}

/// Horizontal bar split into 4 weekly segments; each segment fills with
/// green when its milestone is achieved, accent tint for the current week.
private struct WeeklyProgressBar: View {
    let milestones: [WeeklyMilestone]
    var body: some View {
        GeometryReader { geo in
            let count = max(milestones.count, 1)
            let total = geo.size.width
            let gap: CGFloat = 4
            let segWidth = (total - gap * CGFloat(count - 1)) / CGFloat(count)
            HStack(spacing: gap) {
                ForEach(milestones) { m in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: m))
                        .frame(width: segWidth, height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(m.isCurrent ? Color.accentColor : .clear, lineWidth: m.isCurrent ? 2 : 0)
                        )
                }
            }
        }
        .frame(height: 12)
    }

    private func color(for m: WeeklyMilestone) -> Color {
        if m.isAchieved { return .green }
        if m.isCurrent { return Color.accentColor.opacity(0.5) }
        return Color.secondary.opacity(0.2)
    }
}