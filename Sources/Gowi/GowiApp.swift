import SwiftUI
import AppKit

@main
struct GowiApp: App {
    @StateObject private var auth: AuthService
    @StateObject private var model: AppModel
    @StateObject private var store: RepoStore

    init() {
        let auth = AuthService()
        let store = RepoStore()
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: AppModel(auth: auth, store: store))
    }

    var body: some Scene {
        WindowGroup("gowi", id: "main") {
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

        MenuBarExtra {
            MenuBarRoot()
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(store)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
