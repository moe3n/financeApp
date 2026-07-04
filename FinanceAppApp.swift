import SwiftUI
import SwiftData

@main
struct FinanceAppApp: App {
    let container: ModelContainer

    init() {
        // Local-only SwiftData store — no Apple Developer account / CloudKit needed.
        // To enable iCloud sync later:
        //   1. Switch to a paid Apple Developer account.
        //   2. In Xcode → Signing & Capabilities → add iCloud + CloudKit, create a container.
        //   3. Replace `cloudKitDatabase: .none` with `.private("iCloud.com.yourname.FinanceApp")`.
        let schema = Schema([
            Earning.self,
            Spend.self,
            Installment.self,
            InstallmentPayment.self,
            SavingPlan.self,
            Budget.self,
            NetWorthSnapshot.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(FXRateStore())
                .environmentObject(SpendCategoryStore())
                .environmentObject(NotificationManager())
        }
        .modelContainer(container)
    }
}