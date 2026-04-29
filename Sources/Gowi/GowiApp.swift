import SwiftUI
import AppKit

@main
struct GowiApp: App {
    @StateObject private var auth: AuthService
    @StateObject private var model: AppModel
    @StateObject private var store: RepoStore

    init() {
        // Without a proper .app bundle (we're running via `swift run` during the PoC),
        // macOS won't activate the process as a regular app. Force regular activation
        // policy so a window actually appears and takes focus.
        NSApplication.shared.setActivationPolicy(.regular)

        let auth = AuthService()
        let store = RepoStore()
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: AppModel(auth: auth, store: store))
    }

    var body: some Scene {
        WindowGroup("gowi") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(store)
                .frame(minWidth: 360, minHeight: 420)
        }
        .defaultSize(width: 480, height: 640)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(store)
        }
    }
}
