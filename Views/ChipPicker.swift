import SwiftUI

/// A pill-style picker. Tap a chip to select it. The last chip is "Add…" which
/// opens a one-line prompt — typed once, remembered forever.
struct ChipPicker: View {
    let title: String
    @Binding var selection: String
    @Binding var suggestions: [String]

    @State private var showingAdd = false
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            selection = s
                        } label: {
                            Text(s)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(
                                    selection == s
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(.thinMaterial),
                                    in: Capsule()
                                )
                                .foregroundStyle(selection == s ? Color.white : Color.primary)
                        }
                    }
                    Button {
                        newValue = ""
                        showingAdd = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .alert("Add \(title.lowercased())", isPresented: $showingAdd) {
            TextField(title, text: $newValue)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty else { return }
                if !suggestions.contains(v) { suggestions.append(v) }
                selection = v
            }
        } message: {
            Text("This will be saved and selectable next time.")
        }
    }
}