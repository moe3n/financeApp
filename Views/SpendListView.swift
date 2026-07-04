import SwiftUI
import SwiftData

struct SpendListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore
    @EnvironmentObject private var catStore: SpendCategoryStore
    @Query(sort: \Spend.date, order: .reverse) private var spends: [Spend]

    // catStore is forwarded to the AddSpendView sheet below.

    @State private var showingAdd = false
    @State private var filterCategory: SpendCategory? = nil
    @State private var monthAnchor: Date = Calendar.current.startOfMonth(for: Date())

    private var calendar: Calendar { Calendar.current }

    private var inMonth: [Spend] {
        spends.filter { calendar.isDate($0.date, equalTo: monthAnchor, toGranularity: .month) }
    }

    private var filtered: [Spend] {
        guard let c = filterCategory else { return inMonth }
        return inMonth.filter { $0.category == c.rawValue }
    }

    private var monthTotal: Double {
        inMonth.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(monthLabel(monthAnchor))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(Formatters.baseCurrency(monthTotal, base: fx.base, fx: fx))
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                        }
                        Spacer()
                        MonthStepper(anchor: $monthAnchor)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "All", color: .accentColor,
                                       selected: filterCategory == nil) { filterCategory = nil }
                            ForEach(SpendCategory.allCases) { c in
                                FilterChip(label: c.rawValue, color: c.color,
                                           selected: filterCategory == c) { filterCategory = c }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                ForEach(groupedByDay(filtered), id: \.day) { group in
                    Section(header: HStack {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                        Spacer()
                        Text(Formatters.baseCurrency(group.total, base: fx.base, fx: fx))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }) {
                        ForEach(group.items) { s in
                            SpendRow(spend: s)
                        }
                        .onDelete { idx in
                            for i in idx { context.delete(group.items[i]) }
                        }
                    }
                }

                if filtered.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No spend yet",
                            systemImage: "creditcard",
                            description: Text("Tap + to log your first expense.")
                        )
                    }
                }
            }
            .navigationTitle("Spends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSpendView()
                    .environmentObject(fx)
                    .environmentObject(catStore)
            }
        }
    }

    // MARK: helpers

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private struct DayGroup { var day: Date; var items: [Spend]; var total: Double }

    private func groupedByDay(_ items: [Spend]) -> [DayGroup] {
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { (day, items) in
                DayGroup(
                    day: day,
                    items: items.sorted { $0.date > $1.date },
                    total: items.reduce(0) { fx.convertToBase($1.amount, from: $1.currencyCode) + $0 }
                )
            }
            .sorted { $0.day > $1.day }
    }
}

private struct SpendRow: View {
    @EnvironmentObject private var fx: FXRateStore
    let spend: Spend

    var body: some View {
        let category = SpendCategory(rawValue: spend.category) ?? .extra
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(category.color.opacity(0.18))
                Image(systemName: category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(category.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spend.subcategory.isEmpty ? category.rawValue : spend.subcategory)
                        .font(.headline)
                    if category.needsPayee && !spend.payee.isEmpty {
                        Text("• \(spend.payee)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !spend.note.isEmpty {
                    Text(spend.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("−" + Formatters.currency(spend.amount, code: spend.currencyCode))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }
}

private struct FilterChip: View {
    let label: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                selected ? AnyShapeStyle(color) : AnyShapeStyle(.thinMaterial),
                in: Capsule()
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }
}

private struct MonthStepper: View {
    @Binding var anchor: Date

    var body: some View {
        HStack(spacing: 0) {
            Button {
                anchor = Calendar.current.date(byAdding: .month, value: -1, to: anchor) ?? anchor
            } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            Button { anchor = Calendar.current.startOfMonth(for: Date()) } label: {
                Image(systemName: "circle.dashed").frame(width: 32, height: 32)
            }
            Button {
                anchor = Calendar.current.date(byAdding: .month, value: 1, to: anchor) ?? anchor
            } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.bordered)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = self.dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Add form

struct AddSpendView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateStore
    @EnvironmentObject private var catStore: SpendCategoryStore

    @State private var amount: Double = 0
    @State private var currency: Currency = .usd
    @State private var date = Date()
    @State private var category: SpendCategory = .food
    @State private var subcategory: String = ""
    @State private var payee: String = ""
    @State private var note: String = ""

    @State private var payeeChips: [String] = ["Friend", "Family", "Colleague", "Bank", "Card"]

    private var subSuggestions: [String] { catStore.suggestions(for: category) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInput(amount: $amount, currency: $currency, title: "Amount")
                        .padding(.vertical, 4)
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                        ForEach(SpendCategory.allCases) { c in
                            CategoryTile(category: c, selected: category == c) {
                                category = c
                                subcategory = ""
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ChipPicker(title: "Subcategory", selection: $subcategory, suggestions: Binding(
                        get: { subSuggestions },
                        set: { _ in } // managed via catStore
                    ))
                }

                if category.needsPayee {
                    Section {
                        ChipPicker(title: "Payee", selection: $payee, suggestions: $payeeChips)
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    NoteField(text: $note)
                }
            }
            .navigationTitle("New spend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0)
                }
            }
        }
    }

    private func save() {
        let s = Spend(
            amount: amount, currencyCode: currency.rawValue,
            date: date, category: category.rawValue,
            subcategory: subcategory, payee: payee, note: note
        )
        if !subcategory.isEmpty {
            catStore.add(subcategory, to: category)
        }
        context.insert(s)
        try? context.save()
        dismiss()
    }
}

private struct CategoryTile: View {
    let category: SpendCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(category.color.opacity(selected ? 0.25 : 0.15))
                    Image(systemName: category.symbol)
                        .font(.title3)
                        .foregroundStyle(category.color)
                }
                .frame(width: 44, height: 44)
                Text(category.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                selected ? AnyShapeStyle(category.color.opacity(0.12)) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? category.color : Color.clear, lineWidth: 2)
            )
        }
    }
}