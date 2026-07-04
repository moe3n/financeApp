import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var fx: FXRateStore
    @EnvironmentObject private var notifications: NotificationManager

    @Query(sort: \Earning.date, order: .reverse) private var earnings: [Earning]
    @Query(sort: \Spend.date, order: .reverse)   private var spends: [Spend]
    @Query(sort: \Installment.startDate, order: .reverse) private var installments: [Installment]
    @Query(sort: \SavingPlan.createdAt, order: .reverse)  private var savings: [SavingPlan]
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query(sort: \NetWorthSnapshot.monthStart, order: .reverse) private var netWorthSnapshots: [NetWorthSnapshot]

    @Environment(\.modelContext) private var modelContext
    @State private var exportURLs: [URL] = []
    @State private var showingShareSheet: Bool = false
    @State private var rescheduleTask: Task<Void, Never>? = nil
    @State private var forecastStrategyKind: ForecastStrategyKind = CashFlowForecast.activeStrategyKind
    @State private var backupURL: URL? = nil
    @State private var showingBackupShareSheet: Bool = false
    @State private var showingFileImporter: Bool = false
    @State private var pendingImportURL: URL? = nil
    @State private var showingImportConfirmation: Bool = false
    @State private var backupErrorMessage: String? = nil
    @State private var showingBackupError: Bool = false

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

                Section("Backup & restore") {
                    BackupRestoreSection(
                        earnings: earnings,
                        spends: spends,
                        installments: installments,
                        savings: savings,
                        budgets: budgets,
                        netWorthSnapshots: netWorthSnapshots,
                        onExport: exportBackup,
                        onImport: { showingFileImporter = true }
                    )
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
            .sheet(isPresented: $showingBackupShareSheet) {
                if let url = backupURL { ShareSheet(items: [url]) }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    showingImportConfirmation = true
                case .failure(let error):
                    backupErrorMessage = error.localizedDescription
                    showingBackupError = true
                }
            }
            .alert("Replace all data?", isPresented: $showingImportConfirmation) {
                Button("Cancel", role: .cancel) { pendingImportURL = nil }
                Button("Replace", role: .destructive) {
                    guard let url = pendingImportURL else { return }
                    applyImportedBackup(from: url)
                    pendingImportURL = nil
                }
            } message: {
                Text("All earnings, spends, installments, savings plans, budgets and net-worth snapshots will be replaced with the contents of this backup.")
            }
            .alert("Backup error", isPresented: $showingBackupError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backupErrorMessage ?? "Unknown error.")
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

    /// Write a JSON backup of every model into the temp directory and present
    /// a share sheet so the user can save it to Files / iCloud / etc.
    private func exportBackup() {
        do {
            let url = try BackupCodec.writeBackup(
                earnings: earnings,
                spends: spends,
                installments: installments,
                savings: savings,
                budgets: budgets,
                netWorthSnapshots: netWorthSnapshots
            )
            backupURL = url
            showingBackupShareSheet = true
        } catch {
            backupErrorMessage = error.localizedDescription
            showingBackupError = true
        }
    }

    /// Decode the user-selected JSON backup and replace the current store.
    /// Surfaces an alert on failure; on success, schedules reschedule-all so
    /// installment notifications match the freshly imported state.
    private func applyImportedBackup(from url: URL) {
        // Security-scoped resource dance for files delivered via `.fileImporter`:
        // we must `startAccessing` before reading and `stopAccessing` after.
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let payload = try BackupCodec.readBackup(from: url)
            try BackupStore.applyBackup(payload, to: modelContext)
            scheduleReschedule()
        } catch {
            backupErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            showingBackupError = true
        }
    }
}

/// Section content for `SettingsView`'s "Backup & restore" block. Extracted
/// into its own struct so the Swift type-checker doesn't blow up on the
/// parent view (which is generic over `ModelContext` for `.environment(...)`).
struct BackupRestoreSection: View {

    let earnings: [Earning]
    let spends: [Spend]
    let installments: [Installment]
    let savings: [SavingPlan]
    let budgets: [Budget]
    let netWorthSnapshots: [NetWorthSnapshot]
    let onExport: () -> Void
    let onImport: () -> Void

    private var itemCountLabel: String {
        let total = earnings.count
            + spends.count
            + installments.count
            + savings.count
            + budgets.count
            + netWorthSnapshots.count
        return total == 1 ? "1 item" : "\(total) items"
    }

    var body: some View {
        Button(action: onExport) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up.on.square")
                Text("Export backup (JSON)")
                Spacer(minLength: 8)
                Text(itemCountLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }

        Button(action: onImport) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.on.square")
                Text("Import backup…")
                Spacer(minLength: 8)
            }
        }
        .foregroundStyle(Color.accentColor)

        Text("Importing will replace all current data with the backup. This cannot be undone — export first if you want to keep what's there.")
            .font(.footnote)
            .foregroundStyle(.secondary)
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