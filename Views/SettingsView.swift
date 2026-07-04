import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var fx: FXRateStore
    @EnvironmentObject private var notifications: NotificationManager

    @Query(sort: \Earning.date, order: .reverse) private var earnings: [Earning]
    @Query(sort: \Spend.date, order: .reverse)   private var spends: [Spend]
    @Query(sort: \Installment.startDate, order: .reverse) private var installments: [Installment]
    @Query(sort: \SavingPlan.createdAt, order: .reverse)  private var savings: [SavingPlan]

    @State private var exportURLs: [URL] = []
    @State private var showingShareSheet: Bool = false
    @State private var rescheduleTask: Task<Void, Never>? = nil
    @State private var forecastStrategyKind: ForecastStrategyKind = CashFlowForecast.activeStrategyKind

    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    Button {
                        exportURLs = CSVExporter.writeAllToTemp(
                            earnings: earnings,
                            spends: spends,
                            installments: installments,
                            savings: savings
                        )
                        if !exportURLs.isEmpty { showingShareSheet = true }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export data as CSV")
                            Spacer()
                            Text(itemCountLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Enable reminders", isOn: $notifications.enabled)
                        .onChange(of: notifications.enabled) { _, _ in
                            scheduleReschedule()
                        }
                    if notifications.enabled {
                        Stepper(
                            "Lead time: \(notifications.leadDays) day\(notifications.leadDays == 1 ? "" : "s")",
                            value: $notifications.leadDays,
                            in: 0...14
                        )
                        .onChange(of: notifications.leadDays) { _, _ in
                            scheduleReschedule()
                        }
                    }
                    HStack {
                        Text("Permission")
                            .font(.subheadline)
                        Spacer()
                        Text(notifications.isAuthorized ? "Granted" : "Not granted")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(notifications.isAuthorized ? .green : .secondary)
                    }
                    if !notifications.isAuthorized {
                        Button {
                            Task {
                                _ = await notifications.requestAuthorization()
                                if notifications.isAuthorized {
                                    await notifications.rescheduleAll(
                                        installments: installments,
                                        savings: savings
                                    )
                                }
                            }
                        } label: {
                            Label("Request permission", systemImage: "bell.badge")
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Reminds you N days before an installment due date or a savings deadline. The system will deliver the notification at 9:00 AM local time on the chosen day.")
                }

                Section("Forecast") {
                    Picker("Strategy", selection: $forecastStrategyKind) {
                        ForEach(ForecastStrategyKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: forecastStrategyKind) { _, newKind in
                        CashFlowForecast.setStrategy(newKind)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.secondary)
                        Text("Active: \(forecastStrategyKind.displayName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Base currency") {                    Picker("Base currency", selection: $fx.baseCurrencyRaw) {
                        ForEach(Currency.allCases) { c in
                            Text("\(c.rawValue) (\(c.symbol))").tag(c.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("FX rate = how many \(fx.base.rawValue) equal 1 unit of the other currency. Drag the slider or tap a chip to set it. The app does not fetch rates online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How rates work")
                }

                Section("Exchange rates") {
                    ForEach(Currency.allCases.filter { $0.rawValue != fx.baseCurrencyRaw }) { c in
                        FXRateRow(code: c.rawValue, symbol: c.symbol, base: fx.baseCurrencyRaw)
                            .environmentObject(fx)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: exportURLs)
            }
            .onAppear {
                Task { await notifications.refreshAuthorizationStatus() }
            }
            .onChange(of: installments.count) { _, _ in scheduleReschedule() }
            .onChange(of: savings.count) { _, _ in scheduleReschedule() }
        }
    }

    private var itemCountLabel: String {
        let total = earnings.count + spends.count + installments.count + savings.count
        return total == 1 ? "1 item" : "\(total) items"
    }

    private func scheduleReschedule() {
        rescheduleTask?.cancel()
        rescheduleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // debounce
            if Task.isCancelled { return }
            await notifications.rescheduleAll(
                installments: installments,
                savings: savings
            )
        }
    }
}

struct FXRateRow: View {
    @EnvironmentObject private var fx: FXRateStore
    let code: String
    let symbol: String
    let base: String

    private var rate: Binding<Double> {
        Binding(
            get: { fx.rates[code] ?? 1.0 },
            set: { fx.rates[code] = $0 }
        )
    }

    /// Sensible slider bounds depending on currency strength vs base.
    private var sliderRange: ClosedRange<Double> {
        switch code {
        case "JPY", "INR", "BDT", "PKR": return 0.001...0.1
        case "USD", "CAD", "AUD", "EUR", "GBP": return 0.5...2.0
        default: return 0.01...5.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(symbol) \(code)").font(.headline)
                Spacer()
                Text("1 \(code) = \(String(format: "%.4f", rate.wrappedValue)) \(base)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: rate, in: sliderRange, step: 0.0001)
            HStack(spacing: 6) {
                presetChip(0.5)
                presetChip(1.0)
                presetChip(rate.wrappedValue.rounded() > 0 ? (rate.wrappedValue * 2).rounded() / 2 : 1)
                presetChip(sliderRange.upperBound)
                Spacer()
                Button("Reset") { rate.wrappedValue = 1.0 }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func presetChip(_ v: Double) -> some View {
        Button {
            rate.wrappedValue = max(sliderRange.lowerBound, min(sliderRange.upperBound, v))
        } label: {
            Text(String(format: v < 0.1 ? "%.4f" : "%.2f", v))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
    }
}