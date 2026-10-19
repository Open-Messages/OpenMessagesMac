import AppKit
import SwiftUI

@main
struct OpenMessagesApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("OpenMessages", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 420, minHeight: 480)
        }
        .defaultSize(width: 460, height: 600)

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: "key.viewfinder")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 380)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run`, which has no app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Keep running in the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
