import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: RepoStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { toolbarContent }
        }
        .onAppear { markSeen() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            markSeen()
        }
    }

    // MARK: - content

    @ViewBuilder
    private var content: some View {
        if auth.state != .signedIn {
            SignInView()
        } else if store.repos.isEmpty {
            noReposState
        } else {
            VStack(spacing: 0) {
                if let authURL = model.samlAuthURL {
                    samlBanner(url: authURL)
                }
                switch model.state {
                case .signedOut, .loading:
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let groups):
                    let hasErrors = groups.contains { $0.error != nil }
                    if !hasErrors && (groups.isEmpty || totalPRs(groups) == 0) {
                        allClearState
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
                    errorState(msg)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if auth.state == .signedIn {
            ToolbarItem(placement: .navigation) {
                Text("\(totalPRs(groups)) open")
                    .font(.headline)
                    .monospacedDigit()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.refresh() } label: {
                    ZStack(alignment: .topTrailing) {
                        if model.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        if model.rateLimitWarning {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                                .offset(x: 5, y: -5)
                        }
                    }
                }
                .disabled(model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .help(model.rateLimitWarning ? "Rate limit low — refresh paused" : "Refresh now (⌘R)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    // MARK: - SAML banner

    private func samlBanner(url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub SSO authorization required")
                    .font(.callout).bold()
                Text("Your token needs to be authorized for your organization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Authorize Token") {
                NSWorkspace.shared.open(url)
                model.samlAuthURL = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                model.samlAuthURL = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - states

    private var noReposState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No repositories tracked")
                .font(.title3).bold()
            Text("Add repositories in Settings to start tracking pull requests.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Open Settings") { openSettings() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allClearState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("All clear")
                .font(.title2).bold()
            Text("No open pull requests across tracked repos.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Refresh") { model.refresh() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") { model.refresh() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - helpers

    private var groups: [RepoGroup] {
        if case .loaded(let g) = model.state { return g }
        return []
    }

    private func totalPRs(_ groups: [RepoGroup]) -> Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    private func markSeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSeenAt")
    }
}
