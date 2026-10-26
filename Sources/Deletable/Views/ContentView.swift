import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch state.screen {
            case .home: HomeView()
            case .scanning: ScanningView()
            case .results: ResultsView()
            case .clean: CleanView()
            }
        }
        .alert("Administrator password needed", isPresented: $state.showAdminPrompt) {
            Button(state.adminPermanent ? "Delete with Password…" : "Move to Trash with Password…") {
                state.removeWithAdministrator()
            }
            Button("Cancel", role: .cancel) { state.adminCandidates = [] }
        } message: {
            Text(adminMessage)
        }
        .navigationTitle(title)
        .toolbar { toolbar }
        .alert("Deletable", isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button("OK") { state.alertMessage = nil }
        } message: {
            Text(state.alertMessage ?? "")
        }
    }

    private var adminMessage: String {
        let names = state.adminCandidates.prefix(5).map { "• \($0.name) (\($0.size.formattedBytes))" }
        return "These belong to the system (usually because an installer put them there), so macOS needs your password to remove them:\n\n"
            + names.joined(separator: "\n")
            + (state.adminCandidates.count > 5 ? "\n…" : "")
            + "\n\nIf it's an app with its own uninstaller, using that is cleaner."
    }

    private var title: String {
        switch state.screen {
        case .home: return "Deletable"
        case .scanning: return "Scanning…"
        case .results: return state.root?.displayName ?? "Deletable"
        case .clean: return "Quick Clean"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if state.screen != .home {
                Button {
                    if state.screen == .scanning { state.userCancelledScan() }
                    state.screen = .home
                    state.refreshVolumes()
                } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Back to volumes")
            }
            if state.screen == .results {
                Button { state.goUp() } label: {
                    Label("Up", systemImage: "chevron.up")
                }
                .disabled(state.current?.parent == nil)
                .help("Go to the enclosing folder (⌘↑)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if state.screen == .results {
                Button { state.rescan() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Scan this location again (⌘R)")
            }
        }
    }
}
