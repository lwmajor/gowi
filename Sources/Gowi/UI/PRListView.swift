import SwiftUI
import AppKit

struct PRListView: View {
    let groups: [RepoGroup]
    let onRetry: () -> Void
    let onPullRefresh: () async -> Void

    @State private var collapsed: Set<String> = []

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    if !collapsed.contains(group.id) {
                        body(for: group)
                    }
                } header: {
                    repoHeader(group)
                }
            }
        }
        .listStyle(.inset)
        .refreshable { await onPullRefresh() }
    }

    @ViewBuilder
    private func body(for group: RepoGroup) -> some View {
        if let error = group.error {
            errorRow(error)
        } else if group.pullRequests.isEmpty {
            Text("No open PRs")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(group.pullRequests) { pr in
                PRRow(pr: pr)
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            }
            if group.totalCount > group.pullRequests.count {
                moreFooter(for: group)
            }
        }
    }

    private func moreFooter(for group: RepoGroup) -> some View {
        let shown = group.pullRequests.count
        let total = group.totalCount
        return HStack(spacing: 6) {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
            Text("Showing \(shown) of \(total). View all on GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(group.repo.pullsURL) }
        .help("Open \(group.repo.nameWithOwner) pull requests in browser")
    }

    private func repoHeader(_ group: RepoGroup) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed { collapsed.remove(group.id) }
                    else { collapsed.insert(group.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand" : "Collapse")

            Text(group.repo.nameWithOwner)
                .font(.subheadline).bold()
                .foregroundStyle(.secondary)
                .onTapGesture { NSWorkspace.shared.open(group.repo.pullsURL) }
                .help("Open \(group.repo.nameWithOwner) pull requests in browser")

            Spacer()

            if group.error == nil {
                Text("\(group.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(.link)
        }
    }
}
