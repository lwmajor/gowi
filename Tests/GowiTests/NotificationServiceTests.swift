import XCTest
import UserNotifications

// MARK: - Test doubles

private final class MockCenter: NotificationCenterProtocol {
    var delegate: UNUserNotificationCenterDelegate?
    var addedRequests: [UNNotificationRequest] = []
    var stubbedStatus: UNAuthorizationStatus = .notDetermined

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus { stubbedStatus }
    func add(_ request: UNNotificationRequest) { addedRequests.append(request) }
}

// MARK: - Helpers

private func makePR(id: String, repo: TrackedRepo) -> PullRequest {
    PullRequest(
        id: id,
        number: 1,
        title: "PR \(id)",
        url: URL(string: "https://github.com/\(repo.nameWithOwner)/pull/1")!,
        authorLogin: "author",
        authorAvatarURL: nil,
        isDraft: false,
        createdAt: Date(),
        updatedAt: Date(),
        repo: repo,
        reviewDecision: .noReview,
        checkStatus: .noChecks
    )
}

private func makeGroup(repo: TrackedRepo, prs: [PullRequest] = [], error: String? = nil) -> RepoGroup {
    RepoGroup(repo: repo, pullRequests: prs, totalCount: prs.count, error: error)
}

// MARK: - Tests

@MainActor
final class NotificationServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: RepoStore!
    private var center: MockCenter!

    override func setUp() async throws {
        let uid = UUID().uuidString
        defaults = UserDefaults(suiteName: "gowi.tests.notify.\(uid)")!
        store = RepoStore(defaults: UserDefaults(suiteName: "gowi.tests.notify.store.\(uid)")!)
        center = MockCenter()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaults.description)
        defaults = nil
        store = nil
        center = nil
    }

    private func makeService(enabledRepos: [String] = []) -> NotificationService {
        if !enabledRepos.isEmpty {
            defaults.set(enabledRepos, forKey: "notificationEnabledRepos")
        }
        return NotificationService(store: store, defaults: defaults, center: center)
    }

    // MARK: - Seeding

    func testFirstObserveSeedsSilently() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr = makePR(id: "pr1", repo: repo)
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [pr])])

        XCTAssertTrue(svc.seededRepos.contains(repo.id))
        XCTAssertEqual(svc.seenPRIds[repo.id], ["pr1"])
        XCTAssertTrue(center.addedRequests.isEmpty, "First observe must not post notifications")
    }

    func testSubsequentProcessWithSamePRsPostsNothing() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr = makePR(id: "pr1", repo: repo)
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [pr])])
        svc.process(groups: [makeGroup(repo: repo, prs: [pr])])

        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    // MARK: - New PR detection

    func testNewPRPostsNotificationWhenEnabled() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr1 = makePR(id: "pr1", repo: repo)
        let pr2 = makePR(id: "pr2", repo: repo)
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [pr1])])
        svc.process(groups: [makeGroup(repo: repo, prs: [pr1, pr2])])

        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(center.addedRequests[0].identifier, "pr2")
    }

    func testNewPRDoesNotPostWhenDisabled() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr1 = makePR(id: "pr1", repo: repo)
        let pr2 = makePR(id: "pr2", repo: repo)
        let svc = makeService()  // not enabled

        svc.process(groups: [makeGroup(repo: repo, prs: [pr1])])
        svc.process(groups: [makeGroup(repo: repo, prs: [pr1, pr2])])

        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testFourOrMoreNewPRsPostSummary() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [])])  // seed empty

        let prs = (1...4).map { makePR(id: "pr\($0)", repo: repo) }
        svc.process(groups: [makeGroup(repo: repo, prs: prs)])

        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertTrue(center.addedRequests[0].identifier.hasPrefix("summary-"))
    }

    func testThreeOrFewerNewPRsPostIndividually() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [])])  // seed empty

        let prs = (1...3).map { makePR(id: "pr\($0)", repo: repo) }
        svc.process(groups: [makeGroup(repo: repo, prs: prs)])

        XCTAssertEqual(center.addedRequests.count, 3)
        XCTAssertEqual(Set(center.addedRequests.map(\.identifier)), ["pr1", "pr2", "pr3"])
    }

    // MARK: - Error groups

    func testErrorGroupIsSkipped() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [], error: "rate limited")])

        XCTAssertFalse(svc.seededRepos.contains(repo.id), "Errored group must not seed")
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    // MARK: - seenPRIds replace, not union

    func testSeenIdsReplacedNotUnioned() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr1 = makePR(id: "pr1", repo: repo)
        let pr2 = makePR(id: "pr2", repo: repo)
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [pr1, pr2])])  // seed
        svc.process(groups: [makeGroup(repo: repo, prs: [pr2])])        // pr1 closed

        XCTAssertEqual(svc.seenPRIds[repo.id], ["pr2"],
                       "Closed PR must not accumulate in seenPRIds")
    }

    func testClosedPRTriggersNewNotificationOnReopen() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr1 = makePR(id: "pr1", repo: repo)
        let pr2 = makePR(id: "pr2", repo: repo)
        let svc = makeService(enabledRepos: [repo.id])

        svc.process(groups: [makeGroup(repo: repo, prs: [pr1, pr2])])  // seed
        svc.process(groups: [makeGroup(repo: repo, prs: [pr2])])        // pr1 gone
        svc.process(groups: [makeGroup(repo: repo, prs: [pr1, pr2])])  // pr1 reappears

        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(center.addedRequests[0].identifier, "pr1")
    }

    // MARK: - Persistence

    func testEnabledReposPersistedAcrossReload() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        defaults.set([repo.id], forKey: "notificationEnabledRepos")

        let svc = NotificationService(store: store, defaults: defaults, center: center)
        XCTAssertTrue(svc.enabledRepos.contains(repo.id))

        let reloaded = NotificationService(store: store, defaults: defaults, center: center)
        XCTAssertTrue(reloaded.enabledRepos.contains(repo.id))
    }

    func testSeenIdsPersistedAcrossReload() {
        let repo = TrackedRepo(owner: "apple", name: "swift")
        let pr = makePR(id: "pr1", repo: repo)
        let svc = makeService()

        svc.process(groups: [makeGroup(repo: repo, prs: [pr])])

        let reloaded = NotificationService(store: store, defaults: defaults, center: center)
        XCTAssertEqual(reloaded.seenPRIds[repo.id], ["pr1"])
        XCTAssertTrue(reloaded.seededRepos.contains(repo.id))
    }

    // MARK: - Pruning

    func testPruningRemovesStaleEnabledAndSeenData() async {
        let repoA = TrackedRepo(owner: "apple", name: "swift")
        let repoB = TrackedRepo(owner: "apple", name: "swift-package-manager")
        store.add(repoA)
        store.add(repoB)
        defaults.set([repoA.id, repoB.id], forKey: "notificationEnabledRepos")
        let svc = NotificationService(store: store, defaults: defaults, center: center)

        let prB = makePR(id: "prB1", repo: repoB)
        svc.process(groups: [makeGroup(repo: repoB, prs: [prB])])

        XCTAssertTrue(svc.enabledRepos.contains(repoB.id))
        XCTAssertTrue(svc.seededRepos.contains(repoB.id))

        store.remove(repoB)
        await Task.yield()

        XCTAssertFalse(svc.enabledRepos.contains(repoB.id))
        XCTAssertFalse(svc.seededRepos.contains(repoB.id))
        XCTAssertNil(svc.seenPRIds[repoB.id])
        XCTAssertTrue(svc.enabledRepos.contains(repoA.id))
    }
}
