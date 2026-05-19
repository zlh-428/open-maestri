import SwiftUI

/// 分配角色 Sheet（从右键菜单 "Assign Role" 触发）
/// 展示可用角色列表，选择后回调
struct AssignRoleSheet: View {
    let roles: [RolePreset]
    let onAssign: (RolePreset) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("分配角色").font(.headline)
                Spacer()
                Button("取消") {
                    dismiss()
                    onDismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            if roles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("暂无可用角色")
                        .foregroundStyle(.secondary)
                    Text("请在设置中添加角色预设")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(roles) { role in
                            Button {
                                onAssign(role)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: role.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(hex: role.color) ?? .primary)
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(role.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                        if !role.prompt.isEmpty {
                                            Text(role.prompt)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.clear)
                            )
                            .onHover { hovering in
                                // hover 效果由 SwiftUI 自动处理
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 320, height: 320)
    }
}
