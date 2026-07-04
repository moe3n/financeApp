# FinanceApp

Lightweight iOS personal finance tracker built with **SwiftUI + SwiftData**, stored **locally on-device** (no Apple Developer account, no iCloud, no network).

Tracks three things:
- **Earnings** — money coming in (salary, freelance, gifts, etc.)
- **Installments** — money you *owe* (loans, EMIs, BNPL). Each installment has a principal, interest rate, total months, and a log of payments made.
- **Saving Plans** — goals with a target amount, deadline, and progress.
- **Budgets** — per-category monthly caps with live progress on the dashboard.
- **Net worth** — monthly snapshot history of earnings − spends − outstanding installments + savings, plotted as a chart.
- **Notifications** — opt-in local reminders N days before an installment due date or a savings deadline.
- **Forecast plug-ins** — `ForecastStrategy` protocol with a built-in moving-average implementation; pick the active strategy from Settings.

Multi-currency: pick a base currency in Settings; per-transaction amount is stored in its own currency, and totals are converted using **manually maintained** FX rates stored in `UserDefaults` (no network calls — keeps the app offline-first and lightweight).

---

## Installation

These steps get a fresh checkout building and running in the iOS Simulator.

### Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| macOS | 13+ | Xcode 15+ requires macOS 13 or newer. |
| Xcode | 15.0+ | Brings Swift 5.9 and the iOS 17 SDK. |
| XcodeGen | any | Regenerates `FinanceApp.xcodeproj` from `project.yml`. Install with `brew install xcodegen`. |
| iOS Simulator | 17.0+ | Required runtime; SwiftData ships in iOS 17. |

> No paid Apple Developer account is required — the project uses free personal-team signing out of the box.

### 1. Clone

```bash
git clone https://github.com/<your-account>/FinanceApp.git
cd FinanceApp
```

### 2. Generate the Xcode project

The committed `FinanceApp.xcodeproj/` is a placeholder. Regenerate it from the canonical `project.yml`:

```bash
xcodegen generate
```

This produces a real `FinanceApp.xcodeproj` you can open in Xcode.

### 3. Open and configure signing

```bash
open FinanceApp.xcodeproj
```

In Xcode:

1. Select the `FinanceApp` target → **Signing & Capabilities** tab.
2. Check **Automatically manage signing**.
3. Pick your **Personal Team** in the Team dropdown. Xcode creates a free provisioning profile automatically.
4. If the dropdown is empty, sign in with your Apple ID first: **Xcode → Settings → Accounts → +**.

> Optional: set `DEVELOPMENT_TEAM` in `project.yml` to your 10-character Team ID so other clones pick up the same team without manual setup.

### 4. Run

- Pick an iPhone simulator (iOS 17+) from the run destination dropdown.
- Hit **⌘R** (or the play button).

On first launch the app creates a local SwiftData store in the app's sandbox and lands on the Dashboard.

### 5. Verify

A successful first run shows the Dashboard with three top-level sections: **Net worth**, **Cash-flow forecast**, and **Budgets**. Tabs at the bottom: **Dashboard · Earnings · Spend · Installments · Savings · Budgets · Settings**.

If anything crashes on launch, double-check that the deployment target is **iOS 17.0** (the simulator runtime, not just the SDK).

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

## How to build from the command line

Useful for CI or when you just want a quick sanity check:

```bash
xcodegen generate
rm -rf build
xcodebuild \
  -project FinanceApp.xcodeproj \
  -scheme FinanceApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  -derivedDataPath build \
  clean build
```

Install onto a booted simulator and launch:

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/FinanceApp.app
xcrun simctl launch booted com.financeapp.app
```

---

## Project layout

```
FinanceApp/
├── FinanceAppApp.swift         # @main entry, schema registration, env-object wiring
├── Models/                     # SwiftData @Model types
│   ├── Budget.swift
│   ├── Earning.swift
│   ├── Installment.swift
│   ├── NetWorthSnapshot.swift
│   ├── SavingPlan.swift
│   ├── Spend.swift
│   └── SpendCategory.swift
├── Services/                   # Pure math, FX, notifications, export, strategies
│   ├── BudgetStore.swift
│   ├── CSVExporter.swift
│   ├── Currency.swift
│   ├── FXRateStore.swift
│   ├── ForecastStrategy.swift  # protocol + catalog + CashFlowForecast facade
│   ├── Formatters.swift
│   ├── NetWorthCalculator.swift
│   ├── NotificationManager.swift
│   └── SpendCategoryStore.swift
├── Views/                      # SwiftUI views, one per screen / card
└── project.yml                 # XcodeGen spec — regenerate the .xcodeproj from this
```

### Adding a forecast strategy

1. Add a case to `ForecastStrategyKind` in `Services/ForecastStrategy.swift`.
2. Add a branch in `ForecastStrategyCatalog.make(_:)`.
3. (Optional) Override `displayName` / `shortLabel` on the new case.

The Settings picker and the dashboard chart pick it up automatically with no view-layer changes.

---

## Notes

- **Backup**: with the default local-only setup, your data lives only on the device that installed the app. Uninstalling the app or resetting the simulator wipes it. Keep that in mind until iCloud sync is enabled.
- FX rates live in `UserDefaults` under key `FinanceApp.fxRates` as `[String: Double]` keyed by currency code (e.g. `"USD"`, `"EUR"`). 1 unit of the key currency = N units of your base currency. Edit them in the **Settings** tab.
- Installments auto-generate a schedule of expected payments based on `startDate`, `totalMonths`, and `monthlyAmount`. Mark each paid one from the Installment detail view.
- Notifications require the user to grant permission via the **Request permission** button in Settings. The app schedules them at 9:00 AM local time, N days before the due date (default N=3).
- The forecast chart overlays a muted dashed baseline (`MovingAverageStrategy(windowDays: 90)`) whenever a non-default strategy is active, so divergence is visible at a glance.
