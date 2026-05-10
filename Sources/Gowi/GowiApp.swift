import SwiftUI
import AppKit
import Sparkle

@main
struct GowiApp: App {
    @NSApplicationDelegateAdaptor(GowiAppDelegate.self) private var appDelegate
    @StateObject private var auth: AuthService
    @StateObject private var model: AppModel
    @StateObject private var store: RepoStore
    @StateObject private var notifications: NotificationService
    private let updaterController: SPUStandardUpdaterController

    init() {
        #if DEBUG
        if UITestConfiguration.isEnabled {
            let (auth, store, notifications, model) = UITestConfiguration.makeDependencies()
            _auth = StateObject(wrappedValue: auth)
            _store = StateObject(wrappedValue: store)
            _notifications = StateObject(wrappedValue: notifications)
            _model = StateObject(wrappedValue: model)
            updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            return
        }
        #endif

        let auth = AuthService()
        let store = RepoStore()
        let notifications = NotificationService(store: store)
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: store)
        _notifications = StateObject(wrappedValue: notifications)
        _model = StateObject(wrappedValue: AppModel(auth: auth, store: store, notifications: notifications))
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup("gowi", id: "main") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(store)
                .environmentObject(notifications)
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
                .environmentObject(notifications)
        }

        MenuBarExtra {
            MenuBarRoot()
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(store)
                .environmentObject(notifications)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// On macOS 15+ the SwiftUI `WindowGroup` window does not auto-present at
/// launch when the app also declares a `MenuBarExtra`. The CI runner
/// (Apple VM, macOS 15.7) reproduces this — only the menu bar exists, no
/// `Window` element appears in the accessibility tree, so XCUITest
/// queries return nothing. Trigger the standard "New <App> Window" menu
/// item once the app has finished launching to force the WindowGroup to
/// instantiate its window. Safe on macOS where auto-presentation already
/// works (the menu action is a no-op when a window is already visible).
final class GowiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            guard NSApp.windows.first(where: { $0.canBecomeKey && $0.title.lowercased().contains("gowi") }) == nil else { return }
            guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu,
                  let newWindow = fileMenu.items.first(where: { $0.title.lowercased().hasPrefix("new ") }),
                  let action = newWindow.action
            else { return }
            NSApp.sendAction(action, to: newWindow.target, from: newWindow)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
