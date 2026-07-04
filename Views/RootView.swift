import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            EarningsListView()
                .tabItem { Label("Earnings", systemImage: "arrow.down.circle.fill") }

            SpendListView()
                .tabItem { Label("Spends", systemImage: "arrow.up.circle.fill") }

            InstallmentsListView()
                .tabItem { Label("Installments", systemImage: "calendar.badge.clock") }

            SavingsListView()
                .tabItem { Label("Savings", systemImage: "target") }

            BudgetsListView()
                .tabItem { Label("Budgets", systemImage: "chart.bar.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}