# gowi — Get On With It

A lightweight macOS menu bar + window app that shows open pull requests across a user-configured list of GitHub repositories. Read-only; clicking a PR opens it in the browser.

See `pr-tracker-spec.md` for the full product + technical spec and `TASKS.md` for the commit-sized task breakdown.

## Install

1. Download the latest `gowi-x.y.z.dmg` from [Releases](https://github.com/lwmajor/gowi/releases).
2. Open the DMG and drag **gowi** to `/Applications`.
3. Launch gowi from `/Applications` or Spotlight.
4. Click **Sign in with GitHub** and follow the device-flow prompt in your browser.
5. Open **Settings → Repositories** and add repos in `owner/name` form.

gowi requires macOS 14.0 (Sonoma) or later.

## GitHub permissions

gowi requests one of two OAuth scopes at sign-in:

| Scope | When | Why |
|---|---|---|
| `repo` | Default | Read PRs in private repos you have access to. GitHub does not offer a narrower read-only scope for private repos via OAuth. |
| `public_repo` | If you tick "Public repos only" on the sign-in screen | Read PRs in public repos only. Use this if you only track public repositories. |

gowi is **read-only** — it never opens, closes, merges, or comments on pull requests. No data is sent to any third party; all GitHub communication goes directly to `api.github.com`.

## Status

**0.1.0 alpha** — first public release. The window app is feature-complete for v1: device-flow sign-in, keychain, settings, per-repo PR fetch, batched GraphQL, grouped list, review/CI status icons, new-since dot, collapsible sections, cache, ⌘R / trackpad pull-to-refresh, SAML SSO handling, rate-limit awareness, and menu bar extra. Sparkle auto-update and the distribution pipeline (notarized DMG, appcast) are wired up.

See [`CHANGELOG.md`](CHANGELOG.md) for the full feature list and known limitations. Bug reports welcome on the [issue tracker](https://github.com/lwmajor/gowi/issues).

## Building

The Xcode project is generated from `project.yml` by [xcodegen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen      # once
xcodegen generate           # whenever project.yml changes
open gowi.xcodeproj
```

Or from the command line:

```
xcodebuild -project gowi.xcodeproj -scheme gowi -destination 'platform=macOS' build
xcodebuild -project gowi.xcodeproj -scheme gowi -destination 'platform=macOS' test
```

`gowi.xcodeproj/` is gitignored — regenerate via `xcodegen` after pulling.

## First-run setup

1. Register a GitHub OAuth app at <https://github.com/settings/applications/new>. Enable "Device Flow".
2. Copy the template and fill in your client ID (the real file is gitignored):
   ```
   cp Secrets.swift.template Sources/Gowi/Secrets.swift
   $EDITOR Sources/Gowi/Secrets.swift
   ```
3. Generate the Xcode project:
   ```
   xcodegen generate
   ```
4. Build & run via Xcode (⌘R) or the command line.
5. Click "Sign in with GitHub", follow the device-flow prompt in your browser.
6. Open Settings → Repositories, add `owner/name` entries.

## Layout

```
App/
  Info.plist
  appcast.xml             # Sparkle update feed template
  Gowi.entitlements       # sandbox + network.client only
Sources/Gowi/
  GowiApp.swift           # App entry (scenes + Sparkle updater)
  AppModel.swift          # Observable root state + refresh loop
  Models/                 # PullRequest, TrackedRepo, enums
  Auth/                   # KeychainHelper, DeviceFlowClient, AuthService
  Net/                    # GraphQL client + typed queries + PRMapper
  Settings/               # RepoStore
  UI/                     # Views
Tests/GowiTests/          # XCTest — tests compile sources directly
scripts/
  notarize.sh             # Submit to Apple notary service and staple
  build-dmg.sh            # Full release build → notarized DMG
project.yml               # xcodegen spec
RELEASING.md              # Step-by-step release process
```
