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
                .navigationTitle(windowTitle)
                .toolbar { toolbarContent }
        }
        .onAppear { markSeen() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            markSeen()
        }
    }

    private var windowTitle: String {
        guard auth.state == .signedIn else { return "gowi" }
        let total = totalPRs(groups)
        return total > 0 ? "\(total) open" : "gowi"
    }

    // MARK: - content

    @ViewBuilder
    private var content: some View {
        if auth.state != .signedIn {
            VStack(spacing: 0) {
                if model.tokenRevoked {
                    tokenRevokedBanner
                }
                SignInView()
            }
        } else if store.repos.isEmpty {
            noReposState
        } else {
            VStack(spacing: 0) {
                if model.isShowingCachedData && !model.isRefreshing {
                    cachedDataBanner
                }
                if let authURL = model.samlAuthURL {
                    samlBanner(url: authURL)
                }
                switch model.state {
                case .signedOut, .loading:
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier(AccessibilityID.Main.loading)
                case .loaded:
                    let filtered = model.filteredGroups
                    let hasErrors = filtered.contains { $0.error != nil }
                    if !hasErrors && (filtered.isEmpty || totalPRs(filtered) == 0) {
                        allClearState
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
                    errorState(msg)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if auth.state == .signedIn {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $model.showOnlyAssignedToMe) {
                    Image(systemName: "person.fill")
                }
                .toggleStyle(.button)
                .help("Show only PRs assigned to me")
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
                .accessibilityIdentifier(AccessibilityID.Main.refreshButton)
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

    // MARK: - banners

    private var tokenRevokedBanner: some View {
        inlineBanner(
            icon: "key.slash", accentColor: .red,
            title: "GitHub token revoked",
            message: "Your access token was revoked. Sign in again to continue.",
            onDismiss: { model.tokenRevoked = false },
            rootID: AccessibilityID.Banner.tokenRevoked,
            dismissID: AccessibilityID.Banner.tokenRevokedDismiss
        )
    }

    // MARK: - cached data banner

    private var cachedDataBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            if let last = model.lastRefresh {
                Text("Showing cached data — last refreshed \(last, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Showing cached data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { model.refresh() }
                .font(.caption)
                .buttonStyle(.borderless)
                .accessibilityIdentifier(AccessibilityID.Banner.cachedRetry)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Banner.cached)
    }

    private func samlBanner(url: URL) -> some View {
        inlineBanner(
            icon: "lock.shield", accentColor: .orange,
            title: "GitHub SSO authorization required",
            message: "Your token needs to be authorized for your organization.",
            action: ("Authorize Token", { NSWorkspace.shared.open(url); model.samlAuthURL = nil }),
            onDismiss: { model.samlAuthURL = nil },
            rootID: AccessibilityID.Banner.saml,
            actionID: AccessibilityID.Banner.samlAuthorize,
            dismissID: AccessibilityID.Banner.samlDismiss
        )
    }

    private func inlineBanner(
        icon: String,
        accentColor: Color,
        title: String,
        message: String,
        action: (label: String, handler: () -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        rootID: String? = nil,
        actionID: String? = nil,
        dismissID: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier(actionID ?? "")
            }
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityIdentifier(dismissID ?? "")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(accentColor.opacity(0.10))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rootID ?? "")
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
                .accessibilityIdentifier(AccessibilityID.Main.openSettingsButton)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Main.emptyState)
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
                .accessibilityIdentifier(AccessibilityID.Main.allClearRefreshButton)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Main.allClear)
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
                .accessibilityIdentifier(AccessibilityID.Main.errorRetryButton)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Main.errorState)
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
