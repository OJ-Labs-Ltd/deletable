import SwiftUI
import AppKit

@main
struct DiskLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var cleaner = Cleaner()

    var body: some Scene {
        WindowGroup("DiskLens") {
            ContentView()
                .environmentObject(state)
                .environmentObject(cleaner)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan Folder…") { state.chooseFolderAndScan() }
                    .keyboardShortcut("o")
                Button("Rescan") { state.rescan() }
                    .keyboardShortcut("r")
                    .disabled(state.root == nil)
                Button("Go Up") { state.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(state.current?.parent == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Theme {
    static let background = Color(red: 0.075, green: 0.082, blue: 0.105)
    static let panel = Color(red: 0.105, green: 0.115, blue: 0.145)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
}
