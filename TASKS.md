# gowi — Commit-sized task list

Each bullet = one commit. Each commit should build, pass tests, and leave the app in a runnable state (even if the new surface isn't wired up yet). Commits are grouped by milestone but within a milestone they are *ordered* — later commits depend on earlier ones.

Conventions:
- Commit message prefix tracks the area: `scaffold:`, `auth:`, `settings:`, `net:`, `ui:`, `menu:`, `refresh:`, `cache:`, `polish:`, `dist:`, `test:`, `docs:`.
- Keep commits under ~300 changed lines where possible. If a single bullet grows past that, split it.

---

## M1 — Scaffold, sign-in, settings shell

1. `scaffold:` Create Xcode project `gowi` (macOS app, SwiftUI lifecycle, min macOS 14.0, Swift 5.9). Bundle ID `com.<yourorg>.gowi`.
2. `scaffold:` Add `.gitignore` (Xcode + user state + DerivedData + .DS_Store), LICENSE, and a stub `README.md` pointing to `pr-tracker-spec.md`.
3. `scaffold:` Replace default `ContentView` with a `GowiApp` that declares a `WindowGroup` with an empty `MainWindow` and a `Settings` scene with an empty `SettingsView`. No `MenuBarExtra` yet.
4. `scaffold:` Add app icon placeholder and accent colour in Assets.xcassets.
5. `scaffold:` Add entitlements file enabling App Sandbox + `com.apple.security.network.client` only. Enable Hardened Runtime in build settings.
6. `scaffold:` Add `AppModel` `ObservableObject` with a `@Published var state: PRState = .signedOut` stub enum. Inject via `.environmentObject` into both scenes.
7. `auth:` Add `KeychainHelper` — generic password wrapper with `store(token:)`, `readToken() -> String?`, `deleteToken()`. Service id `com.<yourorg>.gowi.github`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
8. `auth:` Add unit tests for `KeychainHelper` (round-trip, overwrite, delete).
9. `auth:` Add `DeviceFlowClient` — `requestCode() -> DeviceCodeResponse` hitting `POST github.com/login/device/code`. Model `DeviceCodeResponse` (including `verification_uri_complete`).
10. `auth:` Add `pollForToken(deviceCode:interval:)` — polls `POST github.com/login/oauth/access_token`, handles `authorization_pending`, `slow_down`, `access_denied`, `expired_token`.
11. `auth:` Add `AuthService` that orchestrates the two device-flow calls, stores the token via `KeychainHelper`, and exposes `@Published var authState: AuthState`.
12. `ui:` Add `SignInView` — centred "Sign in with GitHub" button, "Public repos only" checkbox (maps to scope), and a second state showing the user code + copy button + "Open GitHub" button. Uses `AuthService`.
13. `ui:` Wire `MainWindow` to show `SignInView` when `authState == .signedOut`, placeholder "Signed in" text otherwise.
14. `settings:` Add `SettingsView` with tabbed shell: General, Repositories, Account. Empty pane bodies.
15. `settings:` Implement General pane: refresh interval `Picker` (1/2/5/10/15/30 min, default 5), persisted to `UserDefaults` under key `refreshIntervalMinutes`.
16. `settings:` Implement General pane: "Launch at login" toggle using `SMAppService.mainApp`. Handle the permission flow (may prompt user once).
17. `settings:` Implement General pane: "Show window on launch" toggle, persisted to `UserDefaults`. Wire to `GowiApp` `init` so `MainWindow` is brought forward accordingly.
18. `settings:` Add `RepoStore` (`ObservableObject`) backed by `UserDefaults` key `trackedRepos` — array of `"owner/name"` strings. CRUD methods: `add`, `remove`, `move`.
19. `settings:` Implement Repositories pane: `List` with drag-to-reorder, delete swipe, and "+" button.
20. `settings:` Add "Add repo" sheet: text field with live `owner/name` regex validation. Calls a stub `validateRepo(_:) async throws` on submit (no network yet — returns success).
21. `settings:` Implement Account pane showing signed-in user placeholder (login = "—" until we fetch viewer) + Sign Out button that clears keychain, cache, and returns to `.signedOut`.

Milestone check: App launches, sign-in works end-to-end against real GitHub, Settings window opens, repos can be added/removed/reordered, sign-out works.

---

## M2 — GraphQL client, single-repo fetch

22. `net:` Add `GitHubClient` with `URLSession` + `async/await`, reading token from `KeychainHelper` and setting `Authorization: bearer` header.
23. `net:` Add GraphQL request/response envelope types (`GraphQLRequest`, `GraphQLResponse<T>` with `data`, `errors`, and top-level `rateLimit`).
24. `net:` Handle 401 — on any 401 response, `GitHubClient` deletes the token and publishes an auth-expired signal the app observes to return to `.signedOut`.
25. `net:` Add `viewerQuery()` hitting `viewer { login avatarUrl }`. Wire the Account pane to show real user data.
26. `net:` Replace the stub `validateRepo(_:)` with a real GraphQL call (`repository(owner:name:) { nameWithOwner }`) surfacing not-found and access-denied errors distinctly.
27. `net:` Add `PullRequest`, `ReviewDecision` (with `.noReview`), `CheckStatus` (with `.noChecks`), and `TrackedRepo` models per §6. `authorLogin` optional.
28. `net:` Add `fetchOpenPRs(for:)` — single-repo GraphQL query per §7. Map `reviewDecision` and `statusCheckRollup.state` to enum values. Handle null `author`.
29. `test:` Unit tests: decoding a canned GraphQL response with a mix of draft/non-draft, null-author, missing-rollup, each `ReviewDecision` value, each `CheckStatus` value.
30. `ui:` Add `PRRow` view — avatar, title, `#num by @author, opened Xd ago`, review icon, CI icon, Draft pill. Click opens URL via `NSWorkspace.shared.open(_:)`.
31. `ui:` Add `PRRow` right-click context menu: "Open in Browser", "Copy Link".
32. `ui:` Main window (signed in, 1+ repos): fetch first tracked repo's PRs on appear, show a flat `List` of `PRRow`. No grouping yet, no refresh.

Milestone check: Sign in, add a repo, see its open PRs rendered with correct status icons.

---

## M3 — Multi-repo fetch, grouping, menu bar, timer, cache

33. `net:` Add batched GraphQL query builder that takes N repos and emits aliased sub-queries (`repo0:`, `repo1:`, …). Default batch size 4. Include top-level `rateLimit { remaining resetAt cost }`.
34. `net:` Add complexity-error detection: on `MAX_NODE_LIMIT_EXCEEDED` / complexity errors, halve batch size and retry. Unit test covers the halving logic.
35. `net:` Per-repo error isolation: a sub-query error in the batch is attached to that repo's result only; other repos succeed.
36. `refresh:` Add `PRRefresher` — async sleep loop at the configured interval. `refreshNow()` is coalesced (one in flight).
37. `refresh:` Subscribe to `NSWorkspace.shared.notificationCenter` `didWakeNotification`. On wake, if interval elapsed since last success, refresh once; otherwise resume the loop.
38. `refresh:` Expose `@Published var lastRefresh: Date?` and `@Published var isRefreshing: Bool` from `PRRefresher`.
39. `ui:` Replace main window flat list with grouped list: section per repo in configured order, section header `owner/name` (clickable → `https://github.com/owner/name/pulls`), count on the right. Empty repo → single muted row.
40. `ui:` Per-repo error row (amber icon + short message + Retry button that refetches that one repo).
41. `ui:` Window toolbar: left = "N open", right = refresh button (spinner when `isRefreshing`) + settings button. Warning badge overlays refresh button when last fetch errored or rate-limit threshold hit.
42. `menu:` Add `MenuBarExtra` scene using `.window` style. Label is `Image(symbol)` alone when count = 0, else `HStack { Image; Text("\(count)") }`.
43. `menu:` Popover content: header (total count, refresh, "Open main window"), the grouped PR list component, footer (last refreshed, settings gear, quit).
44. `menu:` "Open main window" button dismisses popover and brings main window forward (handle activation ordering).
45. `cache:` Add `PRCache` — encode/decode `[RepoGroup]` to JSON at `Application Support/gowi/cache.json` (resolved via `FileManager`, sandbox-safe).
46. `cache:` On launch, synchronously load cache (if present) into `AppModel.state = .loaded(cached)` before the first fetch, so the UI has content immediately.
47. `cache:` On every successful fetch, overwrite cache atomically (`.atomic` write option).
48. `refresh:` "New since" dot: persist `lastSeenAt` in `UserDefaults`. Update it when `MainWindow` or the popover becomes key / gains focus. `PRRow` renders a 6pt blue dot when `pr.updatedAt > lastSeenAt`.
49. `net:` Rate-limit handling: parse `rateLimit` from every GraphQL response. If `remaining < max(100, 10 × cost)`, pause the refresh loop until `resetAt`, set a warning flag, and show the toolbar warning badge.

Milestone check: App shows grouped PRs across many repos, badge updates, refresh runs on timer, cache loads instantly on launch, rate-limit warning triggers when forced.

---

## M4 — Empty/error states, Sparkle, notarization, DMG

50. `ui:` Empty state — signed in, no repos configured: centred message "Add repositories in Settings" + button opening Settings at Repositories pane.
51. `ui:` Empty state — signed in, 0 open PRs anywhere: centred "All clear" with refresh button.
52. `ui:` Error state — refresh failed with no cache: error message + Retry button + link to `https://www.githubstatus.com/`.
53. `ui:` Not-signed-in popover state: icon with no badge; popover shows the same CTA as the window.
54. `ui:` Menu bar icon overlay: small warning dot when last refresh failed but cache is being served.
55. `polish:` Draft pill styling, tooltip on truncated titles, row hover highlight, right-aligned status icon spacing, dark-mode pass.
56. `polish:` Relative-time formatting for "opened Xd ago" (use `RelativeDateTimeFormatter`).
57. `polish:` Accessibility — VoiceOver labels on status icons, row labels ("PR 1234, approved, CI passing, by …"), keyboard navigation in the list.
58. `dist:` Add Sparkle via SPM. Configure `SUFeedURL` in `Info.plist`, generate EdDSA keypair (stored out of repo), commit the public key.
59. `dist:` Add a Sparkle "Check for Updates" menu item in the app menu.
60. `dist:` Developer ID signing + Hardened Runtime verified in build settings. Add a notarize script `scripts/notarize.sh` using `notarytool`.
61. `dist:` Add a `scripts/build-dmg.sh` that builds Release, notarizes, and produces a signed DMG with a background and symlink to /Applications.
62. `dist:` Write an initial `appcast.xml` template and document the release process in `RELEASING.md`.
63. `docs:` Update `README.md` with screenshots, install instructions, and scope disclosure. Confirm `pr-tracker-spec.md` matches what shipped.

Milestone check: Signed, notarized DMG opens, drags to /Applications, launches, passes QA checklist in §11.

---

## Cross-cutting — done as they come up, not in a fixed slot

- `test:` Add unit test for repo input validation (valid `owner/name`, rejects empty, whitespace, too many slashes, invalid chars).
- `test:` Add unit test for refresh coalescing (second `refreshNow()` while one is in flight is a no-op).
- `test:` Add unit test for `PRCache` round-trip.
- `test:` Add unit test for the "new since" dot logic (PR updatedAt vs lastSeenAt).
- `docs:` Inline doc comment on every public type in the `Net` and `Auth` modules.

---

## Deferred (post-v1)

Per §12 — notifications, in-UI filtering, mark-as-read/snooze, GHES, multi-account, issues. Also deferred: snapshot tests (would reintroduce a dependency), menu bar custom `NSImage` badge fallback (only if the `HStack` approach shows layout bugs in practice).
