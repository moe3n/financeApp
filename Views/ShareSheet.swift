import SwiftUI
import UIKit

/// Thin SwiftUI bridge over `UIActivityViewController` so we can present the
/// system share sheet from a `.sheet(isPresented:)` modifier.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    var onCompletion: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        vc.excludedActivityTypes = excludedActivityTypes
        vc.completionWithItemsHandler = { _, _, _, _ in
            onCompletion?()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No-op: share items are set at construction time.
    }
}