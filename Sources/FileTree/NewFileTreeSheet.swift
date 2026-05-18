import SwiftUI

// MARK: - 新建 FileTree Sheet

struct NewFileTreeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultPath: String
    let onConfirm: (String) -> Void
    @State private var path: String

    init(defaultPath: String, onConfirm: @escaping (String) -> Void) {
        self.defaultPath = defaultPath
        self.onConfirm = onConfirm
        _path = State(initialValue: defaultPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建文件树").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { onConfirm(path); dismiss() }
                    .disabled(path.isEmpty)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                HStack {
                    TextField("目录路径", text: $path).textFieldStyle(.roundedBorder)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.begin { response in
                            guard response == .OK, let url = panel.url else { return }
                            path = url.path
                        }
                    }
                }
            }.formStyle(.grouped).padding()
        }
        .frame(width: 400, height: 160)
    }
}
