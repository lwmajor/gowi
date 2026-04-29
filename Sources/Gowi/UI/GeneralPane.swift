import SwiftUI
import ServiceManagement

struct GeneralPane: View {
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes: Int = 5
    @AppStorage("showWindowOnLaunch") private var showWindowOnLaunch: Bool = false

    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    private let intervals = [1, 2, 5, 10, 15, 30]

    var body: some View {
        Form {
            Picker("Refresh every", selection: $refreshIntervalMinutes) {
                ForEach(intervals, id: \.self) { m in
                    Text(m == 1 ? "1 minute" : "\(m) minutes").tag(m)
                }
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            if let err = launchAtLoginError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show main window on launch", isOn: $showWindowOnLaunch)
        }
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // This will typically fail during `swift run` because we lack a
            // proper .app bundle. Surface the error instead of silently failing.
            launchAtLoginError = "Launch-at-login unavailable: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
