import SwiftUI
import AppKit
import Sparkle

@main
struct GowiApp: App {
    @StateObject private var auth: AuthService
    @StateObject private var model: AppModel
    @StateObject private var store: RepoStore
    private let updaterController: SPUStandardUpdaterController

    init() {
        let auth = AuthService()
        let store = RepoStore()
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: AppModel(auth: auth, store: store))
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }

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
