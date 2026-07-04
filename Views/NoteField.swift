import SwiftUI

/// A note field that stays collapsed by default. Tap "Add note" to expand
/// a multiline editor — keeps the form clean for users who don't need one.
struct NoteField: View {
    @Binding var text: String
    @State private var expanded = false
    @FocusState private var focused: Bool

    var body: some View {
        if expanded {
            VStack(alignment: .leading, spacing: 6) {
                Text("Note").font(.subheadline).foregroundStyle(.secondary)
                TextField("Optional note", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focused)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Spacer()
                    Button("Remove note") {
                        text = ""
                        expanded = false
                        focused = false
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .onAppear { if !text.isEmpty { focused = true } }
        } else {
            Button {
                expanded = true
            } label: {
                Label("Add note", systemImage: "text.alignleft")
                    .foregroundStyle(.secondary)
            }
        }
    }
}