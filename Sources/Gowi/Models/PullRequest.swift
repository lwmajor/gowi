import Foundation

enum ReviewDecision: String, Codable {
    case approved
    case changesRequested
    case reviewRequired
    case noReview
}

enum CheckStatus: String, Codable {
    case success
    case failure
    case pending
    case noChecks
}

struct PullRequest: Identifiable, Codable, Hashable {
    let id: String              // GraphQL node ID
    let number: Int
    let title: String
    let url: URL
    let authorLogin: String?    // nil when author account has been deleted
    let authorAvatarURL: URL?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let repo: TrackedRepo
    let reviewDecision: ReviewDecision
    let checkStatus: CheckStatus
}
