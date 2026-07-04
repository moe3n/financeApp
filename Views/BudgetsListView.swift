import SwiftUI
import SwiftData

/// Tab listing every active `Budget` with a quick progress bar, plus an
/// "Add budget" entry that picks an un-budgeted category.
struct BudgetsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fx: FXRateStore

    @Query(sort: \Budget.category) private var budgets: [Budget]
    @Query(sort: \Spend.date, order: .reverse) private var spends: [Spend]

    @State private var showingAddSheet: Bool = false
    @State private var editingBudget: Budget? = nil

    var body: some View {
        NavigationStack {
            Group {
                if budgets.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(budgets) { budget in
                                Button {
                                    editingBudget = budget
                                } label: {
                                    BudgetRow(
                                        budget: budget,
                                        snapshot: snapshot(for: budget),
                                        baseCode: fx.base.rawValue
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteBudgets)
                        } header: {
                            Text("Monthly limits")
                        } footer: {
                            Text("Limits are per calendar month. Over-budget rows turn red; spend is converted to your base currency (\(fx.base.rawValue)) using your FX rates.")
                        }
                    }
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                BudgetEditorSheet(mode: .create(usedCategories: usedCategorySet), defaultCurrency: fx.base.rawValue)
            }
            .sheet(item: $editingBudget) { budget in
                BudgetEditorSheet(mode: .edit(budget), defaultCurrency: fx.base.rawValue)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No budgets yet")
                .font(.headline)
            Text("Set a monthly limit for each spending category to keep an eye on your fixed costs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                showingAddSheet = true
            } label: {
                Label("Add a budget", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding()
    }

    private var usedCategorySet: Set<String> {
        Set(budgets.map(\.category))
    }

    private func snapshot(for budget: Budget) -> BudgetSnapshot {
        let p = BudgetMath.progress(for: budget, spends: spends, now: .now, base: fx.base, fx: fx)
        return BudgetSnapshot(
            id: budget.id,
            category: budget.category,
            spent: p.spent,
            limit: p.limit,
            ratio: p.ratio,
            isOverBudget: p.limit > 0 && p.spent > p.limit
        )
    }

    private func deleteBudgets(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(budgets[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Row

private struct BudgetRow: View {
    let budget: Budget
    let snapshot: BudgetSnapshot
    let baseCode: String

    var body: some View {
        let clamped = min(max(snapshot.ratio, 0), 1.5)
        let progress = clamped / 1.5
        let tint: Color = snapshot.isOverBudget ? .red
            : (snapshot.ratio >= 0.85 ? .orange : .accentColor)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let cat = SpendCategory(rawValue: budget.category) {
                    Image(systemName: cat.symbol)
                        .foregroundStyle(cat.color)
                } else {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.secondary)
                }
                Text(budget.category.isEmpty ? "Untitled" : budget.category)
                    .font(.headline)
                Spacer()
                if snapshot.isOverBudget {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(tint)
            HStack {
                Text("Spent: \(Formatters.currency(snapshot.spent, code: baseCode))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Limit: \(Formatters.currency(snapshot.limit, code: baseCode))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Editor sheet

private enum BudgetEditorMode {
    case create(usedCategories: Set<String>)
    case edit(Budget)
}

private struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let mode: BudgetEditorMode
    let defaultCurrency: String

    @State private var category: String = ""
    @State private var limitText: String = ""
    @State private var currencyCode: String = "USD"
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(availableCategories) { cat in
                            HStack {
                                Image(systemName: cat.symbol)
                                Text(cat.rawValue)
                            }
                            .tag(cat.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Monthly limit") {
                    HStack {
                        Text(currencyCode)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        TextField("0.00", text: $limitText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline.monospacedDigit())
                    }
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(Currency.allCases) { c in
                            Text(c.rawValue).tag(c.rawValue)
                        }
                    }
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(isEditing ? "Edit budget" : "New budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private var availableCategories: [SpendCategory] {
        switch mode {
        case .create(let used):
            return SpendCategory.allCases.filter { !used.contains($0.rawValue) }
        case .edit:
            return SpendCategory.allCases
        }
    }

    private var parsedLimit: Double? {
        let normalized = limitText.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var canSave: Bool {
        !category.isEmpty && (parsedLimit ?? 0) > 0
    }

    private func prefill() {
        switch mode {
        case .create(let used):
            if category.isEmpty {
                category = SpendCategory.allCases.first(where: { !used.contains($0.rawValue) })?.rawValue ?? SpendCategory.allCases.first?.rawValue ?? ""
            }
            if currencyCode == "USD" && defaultCurrency != "USD" {
                currencyCode = defaultCurrency
            }
        case .edit(let budget):
            category = budget.category
            limitText = String(format: "%.2f", budget.monthlyLimit)
            currencyCode = budget.currencyCode
            note = budget.note
        }
    }

    private func save() {
        guard let value = parsedLimit, value > 0 else { return }
        switch mode {
        case .create:
            let b = Budget(
                category: category,
                monthlyLimit: value,
                currencyCode: currencyCode,
                note: note
            )
            modelContext.insert(b)
        case .edit(let budget):
            budget.category = category
            budget.monthlyLimit = value
            budget.currencyCode = currencyCode
            budget.note = note
        }
        try? modelContext.save()
        dismiss()
    }
}