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
    @State private var roleToEdit: RolePreset? = nil

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

            // 搜索框 + 角色网格
            VStack(spacing: 0) {
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
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(80), spacing: 8), count: 4),
                        spacing: 8
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
                    .padding(12)
                }
                .frame(maxHeight: 200)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // 选中角色 prompt 预览
            if let role = selectedRole {
                HStack(alignment: .top, spacing: 8) {
                    Text(role.prompt.isEmpty ? "role.picker.prompt_placeholder".localized : role.prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(role.prompt.isEmpty ? .tertiary : .primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        roleToEdit = role
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                Color.clear
                    .frame(height: 44)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            // 底部操作行
            HStack {
                Button {
                    onDiscover()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                        Text("role.picker.discover")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onUnassign()
                } label: {
                    Text("role.picker.unassign")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(selectedRoleId == nil)
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
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected
                              ? (Color(hex: role.color) ?? .blue).opacity(0.12)
                              : Color(nsColor: .controlBackgroundColor))
                        .frame(width: 80, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        )
                    Image(systemName: role.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: role.color) ?? .blue)
                }
                Text(role.name)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新建卡片

private struct NewRoleCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                        .foregroundStyle(Color(nsColor: .separatorColor))
                        .frame(width: 80, height: 80)
                    Image(systemName: "plus")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                Text("role.picker.new")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
    }
}
