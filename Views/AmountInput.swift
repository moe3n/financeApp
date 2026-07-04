import SwiftUI

/// Tap-based amount entry. No keyboard. Big digit buttons, a decimal, a backspace,
/// and quick "chips" for round amounts in the selected currency.
struct AmountInput: View {
    @Binding var amount: Double
    @Binding var currency: Currency
    let title: String

    @State private var display: String = "0"
    @State private var lastSynced: Double = 0

    private let quickAmounts: [Double] = [10, 50, 100, 500, 1000, 5000]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { c in
                            Text("\(c.rawValue) (\(c.symbol))").tag(c)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currency.symbol).bold()
                        Text(currency.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(currency.symbol).font(.title2).foregroundStyle(.secondary)
                Text(display).font(.system(size: 44, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer()
                Button { backspace() } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            keypad

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(quickAmounts, id: \.self) { v in
                        Button { append(v.formatted()) } label: {
                            Text("+\(Formatters.currency(v, code: currency.rawValue))")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                    Button { amount = 0; display = "0" } label: {
                        Text("Clear")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear { syncFromAmount() }
        .onChange(of: amount) { _, new in
            if abs(new - lastSynced) > 0.0001 { syncFromAmount() }
        }
    }

    private var keypad: some View {
        let keys: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [".", "0", "⌫"]
        ]
        return VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { k in
                        Button { tap(k) } label: {
                            Text(k)
                                .font(.title2.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func tap(_ k: String) {
        switch k {
        case "⌫": backspace()
        case ".":
            if !display.contains(".") { display = display == "0" ? "0." : display + "." }
        default:
            if display == "0" { display = k } else { display += k }
        }
        commit()
    }

    private func append(_ s: String) {
        if display == "0" { display = s } else { display += s }
        commit()
    }

    private func backspace() {
        if display.count <= 1 { display = "0" }
        else { display.removeLast() }
        commit()
    }

    private func commit() {
        let parsed = Double(display) ?? 0
        lastSynced = parsed
        amount = parsed
    }

    private func syncFromAmount() {
        lastSynced = amount
        if amount == 0 {
            display = "0"
        } else if amount == amount.rounded() {
            display = String(Int(amount))
        } else {
            display = String(amount)
        }
    }
}