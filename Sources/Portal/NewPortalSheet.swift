import SwiftUI

// MARK: - 新建 Portal Sheet

struct NewPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String, String) -> Void
    @State private var name = ""
    @State private var url = "https://"

    var body: some View {
        VStack(spacing: 0) {
            Text("portal.new")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("portal.name_label")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("portal.name_placeholder", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 12) {
                    Text("portal.url_label")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("portal.url_placeholder", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            HStack {
                Spacer()
                Button("button.cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("button.create") { onConfirm(name, url); dismiss() }
                    .disabled(url.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 480, height: 190)
    }
}
