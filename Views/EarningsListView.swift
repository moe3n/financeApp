import SwiftUI
import SwiftData

struct EarningsListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateStore
    @Query(sort: \Earning.date, order: .reverse) private var earnings: [Earning]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(earnings) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.source.isEmpty ? e.category : e.source).font(.headline)
                            Text("\(e.category) • \(Formatters.shortDate(e.date))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formatters.currency(e.amount, code: e.currencyCode))
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay { if earnings.isEmpty { ContentUnavailableView("No earnings", systemImage: "arrow.down.circle") } }
            .navigationTitle("Earnings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingAdd) {
                AddEarningView()
                    .environmentObject(fx)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(earnings[i]) }
    }
}

struct AddEarningView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateStore

    @State private var source = ""
    @State private var note = ""
    @State private var amount: Double = 0
    @State private var currency: Currency = .usd
    @State private var date = Date()
    @State private var category = "Salary"

    @State private var sources: [String] = ["Acme Inc.", "Upwork", "Client A", "Family"]
    @State private var categories: [String] = ["Salary", "Freelance", "Gift", "Investment", "Refund", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInput(amount: $amount, currency: $currency, title: "Amount")
                        .padding(.vertical, 4)
                }

                Section {
                    ChipPicker(title: "Source", selection: $source, suggestions: $sources)
                    ChipPicker(title: "Category", selection: $category, suggestions: $categories)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    NoteField(text: $note)
                }
            }
            .navigationTitle("New earning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount <= 0)
                }
            }
        }
    }

    private func save() {
        let e = Earning(
            source: source, note: note,
            amount: amount, currencyCode: currency.rawValue,
            date: date, category: category
        )
        context.insert(e)
        try? context.save()
        dismiss()
    }
}