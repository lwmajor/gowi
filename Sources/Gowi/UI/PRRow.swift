import SwiftUI
import AppKit

struct PRRow: View {
    let pr: PullRequest
    @State private var hovering = false
    // @AppStorage requires a string literal — keep in sync with `AppModel.lastSeenAtKey`.
    @AppStorage("lastSeenAt") private var lastSeenAtTimestamp: Double = 0

    private var isNew: Bool {
        guard lastSeenAtTimestamp > 0 else { return false }
        return pr.updatedAt > Date(timeIntervalSince1970: lastSeenAtTimestamp)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isNew ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)

            avatar
                .frame(width: 24, height: 24)
                .clipShape(Circle())

            if !pr.assignees.isEmpty {
                Divider().frame(maxHeight: 16)
                assigneeAvatarsView
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if pr.isDraft { draftPill }
                    Text(pr.title)
                        .lineLimit(1)
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ReviewIcon(decision: pr.reviewDecision)
            CheckIcon(status: pr.checkStatus)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(pr.url) }
        .contextMenu {
            Button("Open in Browser") { NSWorkspace.shared.open(pr.url) }
            Button("Copy Link") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(pr.url.absoluteString, forType: .string)
            }
        }
        .help(pr.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.PRRow.id(pr.id))
    }

    @ViewBuilder
    private var assigneeAvatarsView: some View {
        HStack(spacing: 3) {
            ForEach(Array(pr.assignees.prefix(3)), id: \.login) { assignee in
                assigneeAvatar(for: assignee)
            }
            if pr.assignees.count > 3 {
                Text("+\(pr.assignees.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func assigneeAvatar(for user: UserRef) -> some View {
        Group {
            if let url = user.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.secondary.opacity(0.2))
                }
            } else {
                Circle().fill(.secondary.opacity(0.2))
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = pr.authorAvatarURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.secondary.opacity(0.2))
            }
        } else {
            Circle().fill(.secondary.opacity(0.2))
        }
    }

    private var draftPill: some View {
        Text("Draft")
            .font(.caption2).bold()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
    }

    private var metaLine: String {
        let author = pr.authorLogin.map { "@\($0)" } ?? "unknown"
        let relative = Self.relativeFormatter.localizedString(for: pr.createdAt, relativeTo: .now)
        return "#\(pr.number) by \(author), opened \(relative)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

private struct StatusIconPlaceholder: View {
    var body: some View { Color.clear.frame(width: 16, height: 16) }
}

struct ReviewIcon: View {
    let decision: ReviewDecision
    var body: some View {
        switch decision {
        case .approved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Approved")
        case .changesRequested:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("Changes requested")
        case .reviewRequired:
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .help("Review required")
        case .noReview:
            StatusIconPlaceholder()
        }
    }
}

struct CheckIcon: View {
    let status: CheckStatus
    var body: some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Checks passing")
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("Checks failing")
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.yellow)
                .help("Checks pending")
        case .noChecks:
            StatusIconPlaceholder()
        }
    }
}
