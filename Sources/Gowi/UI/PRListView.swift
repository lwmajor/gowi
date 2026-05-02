import SwiftUI
import AppKit

struct PRListView: View {
    let groups: [RepoGroup]
    let onRetry: (TrackedRepo?) -> Void
    let onPullRefresh: () async -> Void

    @EnvironmentObject private var model: AppModel
    @State private var collapsed: Set<String> = []

    var body: some View {
        List {
            ForEach(groups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { !collapsed.contains(group.id) },
                        set: { expanded in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if expanded { collapsed.remove(group.id) }
                                else { collapsed.insert(group.id) }
                            }
                        }
                    )
                ) {
                    body(for: group)
                } label: {
                    repoHeader(group)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if collapsed.contains(group.id) {
                                    collapsed.remove(group.id)
                                } else {
                                    collapsed.insert(group.id)
                                }
                            }
                        }
                }
            }
            .onMove { model.moveRepo(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
        .refreshable { await onPullRefresh() }
    }

    @ViewBuilder
    private func body(for group: RepoGroup) -> some View {
        if let error = group.error {
            errorRow(error, repo: group.repo)
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
        HStack(spacing: 8) {
            Text(group.repo.nameWithOwner)
                .font(.subheadline).bold()
                .foregroundStyle(.secondary)

            Spacer()

            if group.error == nil {
                Text("\(group.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .help("Right-click to open in browser")
        .contextMenu {
            Button("Open \(group.repo.nameWithOwner) in Browser") {
                NSWorkspace.shared.open(group.repo.pullsURL)
            }
        }
    }

    private func errorRow(_ message: String, repo: TrackedRepo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Retry") { onRetry(repo) }
                .buttonStyle(.link)
        }
    }
}
