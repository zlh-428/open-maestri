import SwiftUI

/// 分配角色 Sheet（从右键菜单 "Assign Role" 触发）
/// 展示可用角色列表，支持分配和取消分配
struct AssignRoleSheet: View {
    let roles: [RolePreset]
    let currentRoleId: UUID?
    let onAssign: (RolePreset) -> Void
    let onUnassign: () -> Void
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
                        // 取消分配选项（仅当已有角色时显示）
                        if currentRoleId != nil {
                            Button {
                                onUnassign()
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, height: 24)

                                    Text("取消分配")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }

                        // 角色列表
                        ForEach(roles) { role in
                            let isCurrentRole = role.id == currentRoleId
                            Button {
                                if !isCurrentRole {
                                    onAssign(role)
                                }
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

                                    // 当前已分配标记
                                    if isCurrentRole {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isCurrentRole ? Color.accentColor.opacity(0.08) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 340, height: 360)
    }
}
