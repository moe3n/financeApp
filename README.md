# FinanceApp

Lightweight iOS personal finance tracker built with **SwiftUI + SwiftData**, stored **locally on-device** (no Apple Developer account, no iCloud, no network).

Tracks three things:
- **Earnings** — money coming in (salary, freelance, gifts, etc.)
- **Installments** — money you *owe* (loans, EMIs, BNPL). Each installment has a principal, interest rate, total months, and a log of payments made.
- **Saving Plans** — goals with a target amount, deadline, and progress.

Multi-currency: pick a base currency in Settings; per-transaction amount is stored in its own currency, and totals are converted using **manually maintained** FX rates stored in `UserDefaults` (no network calls — keeps the app offline-first and lightweight).

---

## One-time Xcode setup

1. **Create the Xcode project** (do this once, then drop the files from this folder in):
   - Xcode → File → New → Project → **iOS** → **App**
   - Product Name: `FinanceApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **SwiftData** (check the box)
   - Minimum deployments: **iOS 17.0** (required for SwiftData)
   - Save the project alongside this `FinanceApp/` source folder.

2. **Replace the generated files**: delete the auto-generated `ContentView.swift`, `FinanceAppApp.swift`, and any `Item.swift`. Drag everything from this `FinanceApp/` folder into the Xcode project navigator (check "Copy items if needed" and add to the `FinanceApp` target).

3. **Signing** (free personal team is fine — no paid account required):
   - Select the project → **Signing & Capabilities** tab → target `FinanceApp`.
   - Check **Automatically manage signing** and pick your **Personal Team** (Xcode auto-generates a free provisioning profile).
   - If you don't see a team, sign in with your Apple ID in Xcode → **Settings → Accounts** first.

4. **Run on a simulator or a real device**. On first launch the app creates the SwiftData store in the app's local sandbox.

---

## Optional: enable iCloud sync later

If you later get a paid Apple Developer account and want to sync across your devices:

1. **Signing & Capabilities** → **+ Capability** → **iCloud** → enable **CloudKit** → add a container (e.g. `iCloud.com.yourname.FinanceApp`).
2. In `FinanceApp/FinanceAppApp.swift`, change:
   ```swift
   cloudKitDatabase: .none
   ```
   to:
   ```swift
   cloudKitDatabase: .private("iCloud.com.yourname.FinanceApp")
   ```
3. Rebuild. The SwiftData models are already written to be CloudKit-compatible (every field optional or with a default, no unique constraints), so no schema changes are needed.

---

## Notes

- **Backup**: with the default local-only setup, your data lives only on the device that installed the app. Uninstalling the app or resetting the simulator wipes it. Keep that in mind until iCloud sync is enabled.
- FX rates live in `UserDefaults` under key `FinanceApp.fxRates` as `[String: Double]` keyed by currency code (e.g. `"USD"`, `"EUR"`). 1 unit of the key currency = N units of your base currency. Edit them in the **Settings** tab.
- Installments auto-generate a schedule of expected payments based on `startDate`, `totalMonths`, and `monthlyAmount`. Mark each paid one from the Installment detail view.