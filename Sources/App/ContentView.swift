import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateWorkspace = false
    @State private var selectedWorkspaceId: UUID?

    var body: some View {
        if !appState.hasCompletedOnboarding {
            OnboardingView(hasCompleted: Binding(
                get: { appState.hasCompletedOnboarding },
                set: { done in
                    appState.hasCompletedOnboarding = done
                    appState.forceSave(cleanShutdown: false)
                }
            ))
        } else {
            mainView
        }
    }

    @State private var showLoadError = false

    @ViewBuilder
    private var mainView: some View {
        NavigationSplitView {
            WorkspaceSidebarView(
                selectedId: $selectedWorkspaceId,
                showCreate: $showCreateWorkspace
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            if let id = selectedWorkspaceId,
               let ws = appState.workspaces.first(where: { $0.id == id }) {
                WorkspaceCanvasView(
                    workspace: ws,
                    backgroundMode: appState.preferences.canvasBackground
                )
                .id(ws.id)  // 工作区切换时强制重建 Canvas，但 PTY 通过 TerminalProviderRegistry 持续存活
            } else {
                EmptyCanvasPlaceholder()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showCreateWorkspace) {
            CreateWorkspaceSheet()
        }
        .onAppear {
            selectedWorkspaceId = appState.activeWorkspaceId
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCreateWorkspace)) { _ in
            showCreateWorkspace = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceCreated)) { notif in
            if let id = notif.userInfo?["workspaceId"] as? UUID {
                selectedWorkspaceId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextWorkspace)) { _ in
            navigateWorkspace(direction: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .prevWorkspace)) { _ in
            navigateWorkspace(direction: -1)
        }
        .onAppear {
            if !appState.loadErrors.isEmpty { showLoadError = true }
        }
        .alert("alert.workspace.load_failed", isPresented: $showLoadError) {
            Button("button.ok") { showLoadError = false }
        } message: {
            Text(appState.loadErrors.joined(separator: "\n"))
        }
    }  // end mainView

    private func navigateWorkspace(direction: Int) {
        let entries = appState.manifest.workspaces
        guard !entries.isEmpty else { return }
        if let current = selectedWorkspaceId,
           let idx = entries.firstIndex(where: { $0.id == current }) {
            let next = (idx + direction + entries.count) % entries.count
            selectedWorkspaceId = entries[next].id
        } else {
            selectedWorkspaceId = entries.first?.id
        }
        appState.selectWorkspace(id: selectedWorkspaceId)
    }
}

