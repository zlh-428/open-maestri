import SwiftUI

// MARK: - 新建 Portal Sheet

struct NewPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String) -> Void
    @State private var url = "https://"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建 Portal").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { onConfirm(url); dismiss() }
                    .disabled(url.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }.formStyle(.grouped).padding()
        }
        .frame(width: 360, height: 160)
    }
}
