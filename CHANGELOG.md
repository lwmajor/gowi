# Changelog

All notable changes to gowi are documented here. Versions follow
[Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-05-01 (alpha)

First public alpha. The window app is feature-complete for v1; the
distribution pipeline (signed/notarized DMG, Sparkle appcast) is wired
up and ready for the first release.

### Sign-in & accounts
- GitHub OAuth Device Flow sign-in.
- Token stored in the macOS Keychain
  (`com.lloydmajor.gowi.github`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- "Public repos only" option on the sign-in screen (uses `public_repo`
  scope; otherwise `repo`).
- Automatic sign-out on 401, with a clear path back to sign-in.
- SAML SSO detection: a banner with an "Authorize Token" button appears
  when an org requires SSO authorization.

### Repositories
- Add, remove, and reorder tracked repos (`owner/name`) from
  Settings → Repositories.
- Live `owner/name` validation on the add sheet, plus a real GraphQL
  validation call that distinguishes "not found" from "no access".
- Per-repo error rows in the list (with retry) so a single bad repo
  doesn't take down the rest.

### PR list
- Grouped list: one section per repo in configured order, with
  `owner/name` header (clickable to the repo's pulls page) and count.
- Per-PR row: avatar, title, `#num by @author, opened Xd ago`, review
  decision icon, CI status icon, Draft pill.
- Click row to open the PR in the browser; right-click for
  "Open in Browser" / "Copy Link".
- "New since" 6pt dot when `pr.updatedAt > lastSeenAt`; cleared when
  the window/popover gains focus.
- Empty states: no repos configured, no open PRs anywhere, refresh
  failed with no cache.

### Network
- GraphQL client (GitHub API v4) with batched aliased queries
  (`repo0:`, `repo1:`, …) and per-repo error isolation.
- `MAX_NODE_LIMIT_EXCEEDED` complexity errors halve the batch size and
  retry.
- Rate-limit awareness: `rateLimit { remaining, resetAt, cost }` parsed
  from every response; refresh loop pauses near the limit and the
  toolbar shows a warning badge.

### Refresh
- Configurable interval (1, 2, 5, 10, 15, 30 min; default 5).
- ⌘R, toolbar refresh button, and trackpad pull-to-refresh.
- Wake-from-sleep refresh via `NSWorkspace.didWakeNotification`.
- Coalesced `refreshNow()` (second call while one is in flight is a
  no-op).

### Cache
- `[RepoGroup]` written atomically to
  `~/Library/Application Support/gowi/cache.json` after every
  successful fetch; loaded synchronously on launch so the UI has
  content immediately.

### Menu bar extra
- `MenuBarExtra` with `.window` style. Label is icon-only when count =
  0, otherwise icon + count.
- Popover: header (total count, refresh, "Open main window"), grouped
  PR list, footer (last refreshed, settings gear, quit).
- Warning dot overlay when last refresh failed but cache is being
  served.

### Polish
- App icon and window logo.
- Toolbar simplified to follow Apple HIG.
- Relative-time formatting ("opened Xd ago") via
  `RelativeDateTimeFormatter`.
- VoiceOver labels on rows and status icons; keyboard navigation in
  the list.
- Dark-mode pass.

### Distribution
- Sparkle 2 via SPM, EdDSA-signed updates, "Check for Updates" menu
  item, `SUEnableInstallerLauncherService` for sandboxed installs.
- `scripts/notarize.sh` (notarytool + staple) and
  `scripts/build-dmg.sh` (Release build → notarize → signed DMG with
  background and `/Applications` symlink).
- `App/appcast.xml` template and `RELEASING.md` documenting the
  release process.

### Build
- App Sandbox enabled, `com.apple.security.network.client` only.
- Hardened Runtime enabled.
- macOS 14.0 (Sonoma) deployment target, Swift 5.9.
- Xcode project generated from `project.yml` via xcodegen.
- GitHub Actions CI builds and tests on every push to `main`.

### Known limitations
- `CFBundleShortVersionString` must be three numeric components, so
  the alpha designation lives in the GitHub release / tag and not in
  the in-app version string.
- After authorizing a SAML token, the user has to refresh manually.
- No notifications, in-UI filtering, mark-as-read/snooze, GitHub
  Enterprise, multi-account, or issues — all deferred per spec §12.
