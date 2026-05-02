# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**gowi** ("Get On With It") is a native macOS menu bar + window app that shows open pull requests across a user-configured list of GitHub repositories. Read-only — clicking a PR opens it in the browser. See `pr-tracker-spec.md` for the full spec and `TASKS.md` for the commit-sized task breakdown (milestones M1–M4).

## Build system

The Xcode project is **generated** from `project.yml` by [xcodegen](https://github.com/yonaskolb/XcodeGen). `gowi.xcodeproj/` is gitignored — regenerate it after pulling or editing `project.yml`:

```sh
xcodegen generate
```

Build and test from the command line:

```sh
xcodebuild -scheme gowi -destination 'platform=macOS' build
xcodebuild -scheme gowi -destination 'platform=macOS' test

# Run a single test class
xcodebuild -scheme gowi -destination 'platform=macOS' test -only-testing GowiTests/PRMapperTests
```

## First-run requirement

`Sources/Gowi/Secrets.swift` is gitignored and must exist before building:

```sh
cp Secrets.swift.template Sources/Gowi/Secrets.swift
# Fill in your GitHub OAuth App client ID
```

Register a GitHub OAuth App at https://github.com/settings/applications/new with Device Flow enabled.

## Architecture

Four `ObservableObject` singletons are created in `GowiApp.init()` and injected via `.environmentObject` into all scenes:

- **`AuthService`** — owns the device-flow OAuth lifecycle and keychain token. Exposes `@Published var state: AuthState` (`.signedOut`, `.awaitingUserCode`, `.signedIn`, `.failed`). Views observe this to gate the UI.
- **`RepoStore`** — persists tracked repos to `UserDefaults` as `["owner/name"]` strings. CRUD only.
- **`AppModel`** — the root fetch/state machine. Subscribes to both `AuthService.$state` and `RepoStore.$repos` via Combine. On sign-in or repo change it triggers a batch fetch and updates `@Published var state: PRState` (`.signedOut`, `.loading`, `.loaded([RepoGroup])`, `.error`). Also owns the periodic tick loop and rate-limit pause logic.
- **`NotificationService`** — owns macOS notification authorization, the per-repo opt-in set (`enabledRepos`), and a persisted seen-PR-IDs map. `AppModel` calls `process(groups:)` after each refresh; the service seeds first-time-observed repos silently, skips errored groups, and posts a banner per new PR (or a summary when more than three arrive at once). Tapping a notification opens the PR URL via `NSWorkspace`.

`AppModel` holds a `GitHubClient` whose token is supplied lazily via a closure (`{ auth?.accessToken }`) so it always reflects the current keychain state without holding a strong ref to `AuthService`.

### Network layer (`Sources/Gowi/Net/`)

- **`GitHubClient`** — stateless GraphQL client (GitHub v4, `https://api.github.com/graphql`). All requests go through `execute(_:)` which maps HTTP errors to `GitHubError` cases. Throws `.unauthorized` on 401 (caller signs out), `.samlRequired(URL)` on 403 with `X-GitHub-SSO` header.
- **`GitHubQueries`** — typed queries (`fetchViewer`, `validateRepo`, `fetchOpenPRs`) as extensions on `GitHubClient`. Uses `send<T>()` which decodes the GraphQL envelope and propagates `.graphQL`, `.notFound`, `.samlRequired` errors.
- **`BatchFetcher`** — builds aliased multi-repo GraphQL queries (`repo0:`, `repo1:`, …), decodes partial results so a per-repo error doesn't fail the whole batch, and halves the batch size on `MAX_NODE_LIMIT_EXCEEDED` errors before retrying. Uses `sendRaw()` to get untyped `Data` for manual decoding.
- **`PRMapper`** — maps `PRWire` (the GraphQL wire type) to the `PullRequest` domain model, including `ReviewDecision` and `CheckStatus` enums.

### Error handling conventions

`GitHubError` cases and their expected handling:
- `.unauthorized` → `auth.signOut()` (all callers do this)
- `.samlRequired(url)` → set `AppModel.samlAuthURL`; the main window shows a banner with an "Authorize Token" button that opens `url`
- `.notFound` → shown per-repo in the grouped list
- `.graphQL`, `.http`, `.transport` → shown as `lastError` or per-repo error row

### Persistence

| Store | Mechanism | Key/Path |
|---|---|---|
| OAuth token | macOS Keychain | service `com.lloydmajor.gowi.github` |
| Tracked repos | `UserDefaults` | `trackedRepos` |
| Refresh interval | `UserDefaults` | `refreshIntervalMinutes` |
| Last seen (new-PR dot) | `UserDefaults` | `lastSeenAt` |
| PR list cache | JSON file | `~/Library/Application Support/gowi/cache.json` |
| Notification-enabled repos | `UserDefaults` | `notificationEnabledRepos` |
| Notification seen PR IDs | `UserDefaults` | `seenPRIds` |
| Notification seeded repos | `UserDefaults` | `seededRepos` |

### Scenes and views

Three SwiftUI scenes declared in `GowiApp`:
- `WindowGroup("gowi", id: "main")` → `MainWindow`
- `Settings` → `SettingsView` (tabs: General, Repositories, Account)
- `MenuBarExtra` (`.window` style) → `MenuBarRoot`

`MainWindow` is the primary decision view — it switches between `SignInView`, empty/error/loading states, and `PRListView` based on `auth.state` and `model.state`. The SAML banner is injected above the content stack when `model.samlAuthURL != nil`.

## Testing

Each service with non-trivial state-machine logic ships with `Tests/GowiTests/<ServiceName>Tests.swift`. Use isolated `UserDefaults` suites (unique suite name per `setUp`) and inject spy doubles via the same injectable parameters the production code exposes. Tests should cover:

- Initial state and persistence across reload
- Core state transitions (happy path and no-op cases)
- Error / skipped cases
- Pruning / cleanup paths

For side-effecting dependencies (network, notification posting, keychain), extract a one-method protocol in the production file and conform the real type via an empty extension. Inject a spy in tests. Do not leave new services untested.

## Commit conventions

Per `TASKS.md`, prefix commits with the area: `scaffold:`, `auth:`, `settings:`, `net:`, `ui:`, `menu:`, `refresh:`, `cache:`, `polish:`, `dist:`, `test:`, `docs:`. Each commit should build and leave the app runnable.

## GitHub SSO / SAML

Orgs with SAML SSO enforcement (e.g. Skyscanner) require OAuth tokens to be explicitly authorized for the org. The app detects this via the `X-GitHub-SSO: required; url=…` header on 403 responses and the `samlRequired(URL)` error case, then prompts the user to authorize their token. After authorizing in the browser the user returns and refreshes manually.
