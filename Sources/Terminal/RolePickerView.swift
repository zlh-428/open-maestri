import SwiftUI

// MARK: - 角色选择器（EditTerminalSheet / NewTerminalSheet 共用）

struct RolePickerView: View {
    let roles: [RolePreset]
    @Binding var selectedRoleId: UUID?
    let onCreateRole: (RolePreset) -> Void
    let onEditRole: (RolePreset) -> Void
    let onUnassign: () -> Void
    let onDiscover: () -> Void

    @State private var searchText: String = ""
    @State private var showNewRoleSheet = false
    @State private var roleToEdit: RolePreset?

    private var filteredRoles: [RolePreset] {
        guard !searchText.isEmpty else { return roles }
        return roles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedRole: RolePreset? {
        guard let id = selectedRoleId else { return nil }
        return roles.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 描述文字
            Text("role.picker.description")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                // 搜索框（深一点的灰色背景）
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    TextField("role.picker.search_placeholder".localized, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .separatorColor).opacity(0.4))
                )
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // 角色网格
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        NewRoleCard { showNewRoleSheet = true }

                        ForEach(filteredRoles) { role in
                            RoleGridCard(
                                role: role,
                                isSelected: selectedRoleId == role.id
                            ) {
                                selectedRoleId = role.id
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .frame(minHeight: 110, maxHeight: 200)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .separatorColor).opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // 选中角色 prompt 预览（灰色背景，与角色网格区域颜色一致）
            if let role = selectedRole {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Text(role.prompt.isEmpty ? "role.picker.prompt_placeholder".localized : role.prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(role.prompt.isEmpty ? .tertiary : .primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        Button {
                            roleToEdit = role
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .separatorColor).opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                Color.clear
                    .frame(height: 0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }

            // 底部操作行
            HStack {
                Spacer()

                Button {
                    onUnassign()
                } label: {
                    Text("role.picker.unassign")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(selectedRoleId == nil)
                .opacity(selectedRoleId == nil ? 0.4 : 1.0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            // Info 说明
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                Text("role.picker.footer")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .environment(\.locale, LocalizationManager.shared.locale)
        .sheet(isPresented: $showNewRoleSheet) {
            RoleEditSheet(role: nil) { newRole in
                onCreateRole(newRole)
                selectedRoleId = newRole.id
            }
            .environment(\.locale, LocalizationManager.shared.locale)
        }
        .sheet(item: $roleToEdit) { role in
            RoleEditSheet(role: role) { updated in
                onEditRole(updated)
                if selectedRoleId == role.id {
                    selectedRoleId = updated.id
                }
            }
            .environment(\.locale, LocalizationManager.shared.locale)
        }
    }
}

// MARK: - 角色网格卡片

private struct RoleGridCard: View {
    let role: RolePreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected
                              ? (Color(hex: role.color) ?? .blue).opacity(0.08)
                              : Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.4),
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        )
                    Image(systemName: role.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: role.color) ?? .blue)
                }
                .frame(width: 64, height: 56)
                Text(role.name)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新建卡片

private struct NewRoleCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Color(nsColor: .separatorColor),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 56)
                Text("role.picker.new")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 80)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
