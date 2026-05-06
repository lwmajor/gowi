import SwiftUI
import AppKit

/// Live badge label for the menu bar icon. Must `@ObservedObject` the model
/// so SwiftUI re-evaluates when `state` changes and the count updates.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
            if totalCount > 0 {
                Text("\(totalCount)").monospacedDigit()
            }
        }
    }

    private var totalCount: Int {
        if case .loaded(let groups) = model.state {
            return groups.reduce(0) { $0 + $1.totalCount }
        }
        return 0
    }
}

/// Popover content shown when the user clicks the menu bar icon.
/// Uses the same `PRListView` as the main window so state stays in sync.
struct MenuBarRoot: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: RepoStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 560)
        .onAppear { markSeen() }
    }

    // MARK: - sections

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(totalCount) open")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button { model.refresh() } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh (⌘R)")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Open main window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if auth.state != .signedIn {
            centred {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text("Not signed in").font(.headline)
                Button("Open main window to sign in") { openMainWindow() }
            }
        } else if store.repos.isEmpty {
            centred {
                Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                Text("No tracked repos").font(.headline)
                Button("Open Settings") { openSettings() }
            }
        } else {
            switch model.state {
            case .signedOut, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let groups):
                if totalCount == 0 {
                    centred {
                        Image(systemName: "checkmark.seal")
                            .font(.largeTitle).foregroundStyle(.green)
                        Text("All clear").font(.headline)
                    }
                } else {
                    PRListView(
                        groups: groups,
                        onRetry: { repo in
                            if let repo { model.refreshSingleRepo(repo) } else { model.refresh() }
                        },
                        onPullRefresh: { await model.performRefresh() }
                    )
                }
            case .error(let msg):
                centred {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(msg)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { model.refresh() }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let last = model.lastRefresh {
                Text("Refreshed \(last, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openSettings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit gowi")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - helpers

    @ViewBuilder
    private func centred<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 10) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var totalCount: Int {
        if case .loaded(let groups) = model.state {
            return groups.reduce(0) { $0 + $1.totalCount }
        }
        return 0
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func markSeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSeenAt")
    }
}
