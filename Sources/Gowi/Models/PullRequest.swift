import Foundation

struct UserRef: Codable, Hashable {
    let login: String
    let avatarURL: URL?
}

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
    let assignees: [UserRef]

    init(
        id: String, number: Int, title: String, url: URL,
        authorLogin: String?, authorAvatarURL: URL?, isDraft: Bool,
        createdAt: Date, updatedAt: Date, repo: TrackedRepo,
        reviewDecision: ReviewDecision, checkStatus: CheckStatus,
        assignees: [UserRef]
    ) {
        self.id = id; self.number = number; self.title = title; self.url = url
        self.authorLogin = authorLogin; self.authorAvatarURL = authorAvatarURL
        self.isDraft = isDraft; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.repo = repo; self.reviewDecision = reviewDecision; self.checkStatus = checkStatus
        self.assignees = assignees
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        authorLogin = try c.decodeIfPresent(String.self, forKey: .authorLogin)
        authorAvatarURL = try c.decodeIfPresent(URL.self, forKey: .authorAvatarURL)
        isDraft = try c.decode(Bool.self, forKey: .isDraft)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        repo = try c.decode(TrackedRepo.self, forKey: .repo)
        reviewDecision = try c.decode(ReviewDecision.self, forKey: .reviewDecision)
        checkStatus = try c.decode(CheckStatus.self, forKey: .checkStatus)
        assignees = try c.decodeIfPresent([UserRef].self, forKey: .assignees) ?? []
    }
}
