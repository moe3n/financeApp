import Foundation
import SwiftUI

/// Persists user-added subcategories per main category, so suggestions grow over time.
/// Backed by UserDefaults under one key, encoded as `[String: [String]]`.
@MainActor
final class SpendCategoryStore: ObservableObject {
    @Published var extras: [String: [String]] {
        didSet { save() }
    }

    private let defaultsKey = "FinanceApp.spendSubcategories"

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: "FinanceApp.spendSubcategories") as? [String: [String]] ?? [:]
        self.extras = saved
    }

    /// All suggestions for a category — defaults plus anything the user has added.
    func suggestions(for category: SpendCategory) -> [String] {
        let custom = extras[category.rawValue] ?? []
        // Dedup while preserving order: defaults first, then unique customs.
        var seen = Set(category.defaultSubcategories)
        var merged = category.defaultSubcategories
        for c in custom where !seen.contains(c) {
            merged.append(c)
            seen.insert(c)
        }
        return merged
    }

    func add(_ sub: String, to category: SpendCategory) {
        var current = extras[category.rawValue] ?? []
        if !current.contains(sub) { current.append(sub) }
        extras[category.rawValue] = current
    }

    private func save() {
        UserDefaults.standard.set(extras, forKey: defaultsKey)
    }
}