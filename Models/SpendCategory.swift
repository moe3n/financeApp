import SwiftUI

/// Main spending categories. The `rawValue` is what gets persisted on `Spend.category`,
/// so don't rename cases — add new ones instead.
enum SpendCategory: String, CaseIterable, Identifiable, Codable {
    case food       = "Food"
    case eatingOut  = "Eating Out"
    case transport  = "Transportation"
    case rent       = "Rent"
    case extra      = "Extra"
    case lend       = "Lend"
    case repay      = "Repay"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .food:      return "cart.fill"
        case .eatingOut: return "fork.knife"
        case .transport: return "car.fill"
        case .rent:      return "house.fill"
        case .extra:     return "ellipsis.circle.fill"
        case .lend:      return "arrow.up.right.circle.fill"
        case .repay:     return "arrow.down.left.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .food:      return .green
        case .eatingOut: return .orange
        case .transport: return .blue
        case .rent:      return .purple
        case .extra:     return .gray
        case .lend:      return .yellow
        case .repay:     return .indigo
        }
    }

    /// Default subcategory suggestions shown the first time the user opens this category.
    /// Users can add more from the form — those go into `SpendCategoryStore`.
    var defaultSubcategories: [String] {
        switch self {
        case .food:
            return ["Groceries", "Vegetables", "Snacks", "Drinks", "Milk/Bread"]
        case .eatingOut:
            return ["Restaurant", "Cafe", "Street food", "Delivery", "Bakery"]
        case .transport:
            return ["Uber/Grab", "Fuel", "Bus/Metro", "Taxi", "Parking", "Tolls"]
        case .rent:
            return ["Rent", "Utilities", "Internet", "Maintenance", "Insurance"]
        case .extra:
            return ["Shopping", "Gadgets", "Health", "Education", "Subscriptions", "Gifts"]
        case .lend:
            return ["Friend", "Family", "Colleague", "Other"]
        case .repay:
            return ["Friend", "Family", "Bank EMI", "Credit Card", "BNPL", "Other"]
        }
    }

    /// Whether this category needs a `payee` field.
    var needsPayee: Bool {
        self == .lend || self == .repay
    }
}