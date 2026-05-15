import SwiftUI
import AppKit

/// Live badge label for the menu bar icon. Must `@ObservedObject` the model
/// so SwiftUI re-evaluates when `state` changes and the count updates.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
            let count = model.state.totalOpenPRs
            if count > 0 {
                Text("\(count)").monospacedDigit()
            }
        }
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
        .onAppear { model.markPRsSeen() }
    }

    // MARK: - sections

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(model.filteredGroups.totalOpenPRs) open")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Toggle(isOn: $model.showOnlyAssignedToMe) {
                Image(systemName: "person.fill")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Show only PRs assigned to me")

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
            case .loaded:
                let filtered = model.filteredGroups
                if filtered.totalOpenPRs == 0 {
                    centred {
                        Image(systemName: "checkmark.seal")
                            .font(.largeTitle).foregroundStyle(.green)
                        Text("All clear").font(.headline)
                    }
                } else {
                    PRListView(
                        groups: filtered,
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
        VStack(spacing: 0) {
            if model.isShowingCachedData && !model.isRefreshing {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                    Text("Cached data")
                        .font(.caption2)
                    Spacer()
                    Button("Retry") { model.refresh() }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                Divider()
            }
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

    private func openMainWindow() {
        openWindow(id: Config.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}
