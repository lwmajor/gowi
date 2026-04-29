# gowi (Get On With It) — macOS PR Tracker — Product & Technical Spec

## 1. Summary

A lightweight native macOS app that shows open pull requests across a user-configured list of GitHub repositories. The app — **gowi**, short for "Get On With It" — runs simultaneously as a menu bar extra (with an open-PR count badge) and as a regular window. It is read-only: clicking a PR opens it in the browser.

## 2. Goals & non-goals

**Goals**
- Give the user an at-a-glance count of open PRs across their tracked repos.
- Show a clean, grouped list of those PRs with enough context (review state, CI) to triage quickly.
- Stay out of the way: native feel, low resource use, minimal config.

**Non-goals (v1)**
- No reviewing, commenting, merging, or any write actions on PRs.
- No support for GitHub Enterprise Server or multi-account.
- No notifications, mark-as-read, or dismissal flows.
- No issue tracking, only PRs.

## 3. Platform & stack

| Area | Choice |
|---|---|
| Min macOS version | 14.0 (Sonoma) |
| Language | Swift 5.9+ |
| UI | SwiftUI, with `MenuBarExtra` for the menu bar surface |
| App lifecycle | `App` protocol with both `WindowGroup` and `MenuBarExtra` scenes |
| Persistence | `UserDefaults` for settings, Keychain for the OAuth token, optional on-disk JSON cache for the last fetched PR list |
| Networking | `URLSession` with `async/await` |
| GitHub API | GraphQL v4 for PR list (single round trip per repo batch), REST v3 only if needed for OAuth device flow endpoints |
| Distribution | Developer ID signed, notarized DMG. Mac App Store optional later. |

Rationale for native SwiftUI: fits the simple-design brief, smallest binary, best menu bar integration, and `MenuBarExtra` (introduced in macOS 13) cleanly supports the simultaneous menu bar plus window setup.

## 4. Authentication

OAuth Device Flow against `github.com`.

**Flow**
1. On first launch (or after sign-out), user clicks "Sign in with GitHub" in the window.
2. App calls `POST https://github.com/login/device/code` with the app's client ID and required scopes.
3. App displays the `user_code`, copies it to the clipboard, and opens `verification_uri_complete` (which pre-fills the code) in the default browser. Falls back to `verification_uri` if `_complete` is missing from the response.
4. App polls `POST https://github.com/login/oauth/access_token` at the interval returned by GitHub (respecting `slow_down`) until the user authorizes or declines.
5. On success, the access token is stored in the macOS Keychain under a single account entry. The token is never written to disk in plaintext or to logs.
6. Sign-out clears the Keychain entry and the on-disk cache.

**Scopes requested:** `repo` (needed to read PRs in private repos the user has access to). This is broader than read-only — the sign-in screen must make that explicit ("gowi only reads; GitHub does not offer a read-only private-repo scope for OAuth apps"). If the user confirms they only track public repos, `public_repo` is sufficient; v1 offers a single "Public repos only" checkbox on the sign-in screen to request the narrower scope.

Fine-grained PATs and GitHub App installation are considered but rejected for v1: PATs break the one-click sign-in UX, and GitHub App device flow has gaps around listing accessible repos.

**Client ID:** registered as a public OAuth app on github.com with Device Flow enabled. No client secret is shipped.

## 5. Configuration & settings

A standard macOS Settings window (`Settings` scene), with these panes:

**General**
- Refresh interval (dropdown: 1, 2, 5, 10, 15, 30 minutes; default 5).
- Launch at login (toggle, via `SMAppService`).
- Show window on launch (toggle, default off).

**Repositories**
- A table listing tracked repos in `owner/name` form.
- Add button: text field with validation against the `owner/name` pattern, plus a live check via the GitHub API that the repo exists and is accessible.
- Remove button.
- Reorder (drag) — controls the display order in the list.
- Stored in `UserDefaults` as an array of strings.

**Account**
- Shows signed-in user (login + avatar).
- Sign out button.

## 6. Data model

```swift
struct TrackedRepo: Codable, Hashable {
    let owner: String
    let name: String
    var nameWithOwner: String { "\(owner)/\(name)" }
}

enum ReviewDecision: String, Codable {
    case approved
    case changesRequested
    case reviewRequired
    case noReview          // avoid collision with Optional.none
}

enum CheckStatus: String, Codable {
    case success
    case failure
    case pending
    case noChecks
}

struct PullRequest: Identifiable, Codable, Hashable {
    let id: String               // GraphQL node ID
    let number: Int
    let title: String
    let url: URL
    let authorLogin: String?     // null when author account was deleted
    let authorAvatarURL: URL?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let repo: TrackedRepo
    let reviewDecision: ReviewDecision
    let checkStatus: CheckStatus
}
```

## 7. GitHub data fetching

**Query strategy**

For each tracked repo, fetch open PRs via a single GraphQL query. Repos are batched into one GraphQL request using aliases (e.g. `repo0:`, `repo1:`...). Start with a batch size of **4 repos per request** (conservative — the `commits(last:1) { statusCheckRollup }` nesting consumes significant complexity points), and tune upwards only after measuring. On a complexity error, halve and retry.

The `viewer { login avatarUrl }` field is included in every request to populate the Account pane and detect identity changes cheaply.

Per-repo fragment, requesting only what the UI needs:

```graphql
pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
  nodes {
    id
    number
    title
    url
    isDraft
    createdAt
    updatedAt
    author { login avatarUrl }
    reviewDecision
    commits(last: 1) {
      nodes {
        commit {
          statusCheckRollup { state }
        }
      }
    }
  }
}
```

`statusCheckRollup.state` maps to `CheckStatus`: `SUCCESS` → success, `FAILURE`/`ERROR` → failure, `PENDING`/`EXPECTED` → pending, missing → none.

`reviewDecision` maps directly: `APPROVED` → approved, `CHANGES_REQUESTED` → changesRequested, `REVIEW_REQUIRED` → reviewRequired, null → none.

**Refresh behaviour**
- On launch, immediately after a successful sign-in, and on the configured interval thereafter.
- Manual refresh: button in the window toolbar and "Refresh now" item in the menu bar popover.
- Refresh runs on a background `Task`. Concurrent refreshes are coalesced (a refresh in flight ignores new tick triggers; the next tick will start a fresh one).
- Scheduling uses a `Task`-based async sleep loop, not `Timer`. On sleep/wake, subscribe to `NSWorkspace.didWakeNotification` and compare `Date.now` against the last successful fetch — if the interval has elapsed, refresh once immediately; otherwise let the loop resume. Never fire a burst of skipped ticks.
- Respect rate limits: read the `rateLimit { remaining, resetAt, cost }` field on every GraphQL response (and `X-RateLimit-Remaining` / `X-RateLimit-Reset` on any REST calls). Threshold: if `remaining` falls below `max(100, 10 × cost)`, pause the refresh loop until `resetAt` and show a subtle warning icon with hover text in the window toolbar.

**Error handling**
- Network failure: keep showing last cached data, show a small warning icon in the window toolbar with hover text describing the error. Menu bar badge stays on the last known count, with a dot indicator on the icon.
- 401 Unauthorized: token has been revoked. Clear it and prompt for sign-in.
- Per-repo errors (e.g. repo deleted, access lost): show that repo's section in the list with an inline error row, but do not block other repos.

**Caching**
- Last successful fetch persisted to `cache.json` inside the app's sandboxed Application Support directory, resolved via `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("gowi/cache.json")`. In a sandboxed app this resolves under `~/Library/Containers/<bundle-id>/Data/Library/Application Support/gowi/`.
- Used to repopulate the UI immediately on launch before the first network call completes.
- Avatar images are served via `AsyncImage`, which uses `URLCache.shared` by default. The default in-memory/disk cache sizes are left unchanged in v1.

**"New since" indicator**

The badge count alone is a glance, not a signal. To make change visible without introducing notifications or mark-as-read flows:

- Persist `lastSeenAt` (a single `Date`) in `UserDefaults`, updated whenever the main window or popover is *brought to the front*.
- Any PR whose `updatedAt > lastSeenAt` renders a small blue dot on the left of the row.
- The dot is purely visual; it does not affect the badge count and has no "mark as read" action. Opening the app clears the dots on next refresh (because `lastSeenAt` advances).

## 8. UI

### 8.1 Menu bar surface

- Icon: a custom SF Symbol style glyph (e.g. a stylised pull request arrow) using `.symbolRenderingMode(.hierarchical)` for light/dark mode parity.
- Badge: total count of open PRs across all tracked repos. If the count is 0, icon only. Otherwise the label is `HStack { Image(...); Text("\(count)") }` passed to `MenuBarExtra`'s label builder. SwiftUI's `MenuBarExtra` accepts an arbitrary `Label` view; `Text` next to `Image` renders correctly in the menu bar on macOS 14+. If layout quirks show up (e.g. inconsistent vertical centring on certain displays), fall back to rendering a template `NSImage` off-screen with the count drawn into it and using `MenuBarExtra(title:image:)`.
- A small warning dot overlays the icon when the last refresh failed but cache is still being shown (see §7).
- Click: opens a popover (`MenuBarExtra(... .window)` style) containing:
  - Header row: total count, a refresh button, and an "Open main window" button.
  - The grouped PR list (same component as the main window, see 8.3).
  - Footer: last refreshed timestamp, settings gear, quit.

### 8.2 Main window

- Single window, restorable, default size around 480x640, resizable, minimum 360x420.
- Toolbar:
  - Left: total PR count (e.g. "12 open").
  - Right: manual refresh button (with spinner state), settings button. A warning badge appears on the refresh button when the last fetch failed or rate limit is approaching.
- Content: the grouped PR list.
- Window can be closed without quitting the app; the menu bar extra remains. Reopened from the menu bar popover or by clicking the Dock icon.
- Dock icon visibility: shown by default. A hidden setting (later) could make it `LSUIElement`-style menu-bar-only, but v1 keeps the Dock icon for discoverability.

### 8.3 PR list (shared component)

Grouped by repo, in the order the user configured in settings. Each group:

- **Section header:** `owner/name` in a slightly muted style, with a count of PRs in that repo on the right. Clickable, opens the repo's PR list in the browser (`https://github.com/owner/name/pulls`).
- **Empty repo:** if a tracked repo has zero open PRs, the section is collapsed to a single muted line "No open PRs" so the user can still see all their tracked repos at a glance. (Toggle in settings later if this becomes noisy.)
- **Per-repo error row:** if the repo-specific GraphQL sub-query failed (repo deleted, access revoked, rate limited, etc.), the section header is preserved but its body is replaced by a single row:
  - Left: amber triangle icon.
  - Centre: short error message ("Repo not found", "Access denied", "Fetch failed — will retry").
  - Right: small "Retry" text button that refetches just that repo.
  - Other repos render normally.
- **New-since-last-seen dot:** when `pr.updatedAt > lastSeenAt`, a 6pt blue dot is drawn to the left of the avatar column. See §7.
- **PR row:**
  - Left: author avatar (small, circular).
  - Main column:
    - Line 1: PR title, truncated with tooltip on hover. Draft PRs prefixed with a "Draft" pill.
    - Line 2 (muted, smaller): `#1234 by @author, opened 3d ago`.
  - Right column: two compact status icons:
    - Review decision: green check (approved), red dot (changes requested), grey dots (review required), nothing (none).
    - CI: green check, red x, yellow dot, nothing.
  - Hover state: subtle row highlight.
  - Click anywhere on the row: opens the PR URL in the user's default browser via `NSWorkspace.shared.open(_:)`.
  - Right-click: context menu with "Open in Browser" and "Copy Link" (small affordance, costs almost nothing to add and is a common ask).

### 8.4 Empty / error states

- **Not signed in:** window shows a centred "Sign in with GitHub" CTA. Menu bar shows the icon with no badge; clicking opens the popover with the same CTA.
- **Signed in, no repos configured:** centred message "Add repositories in Settings" with a button that opens the Repositories pane.
- **Signed in, repos configured, zero open PRs anywhere:** friendly "All clear" state with a refresh button.
- **Refresh failed, no cache:** error message with a Retry button and a link to GitHub's status page.

## 9. Permissions, sandboxing, security

- App Sandbox: enabled.
- Entitlements: `com.apple.security.network.client` only.
- Hardened Runtime: enabled, with no exceptions needed.
- Token storage: Keychain via `SecItemAdd` / `SecItemCopyMatching`, generic password class, service identifier `com.<yourorg>.gowi.github`, accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The `ThisDeviceOnly` variant is deliberate — a device-flow OAuth token is bound to the machine that authorized it, and iCloud Keychain sync is undesirable.
- No analytics, no telemetry, no third-party SDKs in v1.

## 10. Architecture

A small MVVM split:

```
GowiApp (App)
 ├── MenuBarExtra { MenuBarRoot() }
 ├── WindowGroup { MainWindow() }
 └── Settings { SettingsView() }

AppModel (ObservableObject, @MainActor)
 ├── auth: AuthService          // device flow, keychain
 ├── repos: RepoStore           // UserDefaults-backed
 ├── refresher: PRRefresher     // timer + fetch coordination
 ├── github: GitHubClient       // URLSession + GraphQL
 └── state: @Published PRState  // .signedOut | .loading | .loaded([Group]) | .error
```

`AppModel` is created once at app launch and injected into both scenes via `.environmentObject`, so the menu bar and window observe identical state with no syncing logic.

## 11. Build, test, distribution

- Xcode project, single target, Swift Package Manager. v1 ships with exactly one dependency: **Sparkle** for auto-update. All other functionality is stdlib / SwiftUI / AppKit.
- Unit tests for: GraphQL response decoding (including null author, missing rollup), status mapping, refresh coalescing, repo input validation, batch-halving on complexity error.
- No snapshot tests in v1 (would require a second dependency and complicates CI for little gain at this scope). Visual QA is manual.
- Manual QA checklist: sign-in flow, token revocation handling, sleep/wake behaviour (no tick burst), private repo access, very long PR titles, repo with many PRs (50+), deleted-author PR, rate-limit approach.
- Release: notarized DMG, hosted on GitHub Releases, with Sparkle appcast feed hosted alongside the release artifacts. EdDSA signing key for Sparkle is generated and stored outside the repo.

## 12. Open questions for later versions

These are deliberately out of scope for v1 but worth listing so the v1 design does not paint into a corner:

- Notifications when a PR is newly opened, or when one you authored gets a review.
- Filtering inside the UI (e.g. hide drafts, only mine).
- Mark-as-read / snooze.
- GitHub Enterprise Server support (would need a server URL field plus per-account OAuth app).
- Multi-account.
- Showing issues alongside PRs.

## 13. Milestones

1. **M1, week 1:** Project scaffold, sign-in (device flow), token in Keychain, settings window with repo CRUD.
2. **M2, week 2:** GraphQL client, single-repo fetch, basic PR row in the main window.
3. **M3, week 3:** Multi-repo batched fetch, grouped list, menu bar extra with badge, refresh timer, cache.
4. **M4, week 4:** Empty/error states, per-repo error row, status icons, new-since dot, Sparkle integration + appcast, signing and notarization, first DMG.

Timelines assume focused full-time work. For part-time or evenings, plan 2–3× these durations.
