import SwiftUI

// MARK: - 新建 Portal Sheet

struct NewPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String) -> Void
    @State private var url = "https://"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("portal.new").font(.headline)
                Spacer()
                Button("button.cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("button.create") { onConfirm(url); dismiss() }
                    .disabled(url.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("portal.url_placeholder", text: $url)
                    .textFieldStyle(.roundedBorder)
            }.formStyle(.grouped).padding()
        }
        .frame(width: 360, height: 160)
    }
}
