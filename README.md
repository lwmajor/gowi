# gowi — Get On With It

A lightweight macOS menu bar + window app that shows open pull requests across a user-configured list of GitHub repositories. Read-only; clicking a PR opens it in the browser.

See `pr-tracker-spec.md` for the full product + technical spec and `TASKS.md` for the commit-sized task breakdown.

## Status

Pre-v1. Window app works end-to-end (device-flow sign-in, keychain, settings, per-repo PR fetch, grouped list, status icons, collapsible sections, ⌘R / trackpad pull-to-refresh). MenuBarExtra, cache, Sparkle, and distribution are the remaining milestones.

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
2. Put the Client ID in `Sources/Gowi/Config.swift` (replace the existing value).
3. Build & run via Xcode (⌘R) or the command line.
4. Click "Sign in with GitHub", follow the device-flow prompt in your browser.
5. Open Settings → Repositories, add `owner/name` entries.

## Layout

```
App/
  Info.plist
  Gowi.entitlements       # sandbox + network.client only
Sources/Gowi/
  Config.swift            # OAuth client ID
  GowiApp.swift           # App entry (scenes)
  AppModel.swift          # Observable root state + refresh loop
  Models/                 # PullRequest, TrackedRepo, enums
  Auth/                   # KeychainHelper, DeviceFlowClient, AuthService
  Net/                    # GraphQL client + typed queries + PRMapper
  Settings/               # RepoStore
  UI/                     # Views
Tests/GowiTests/          # XCTest — tests compile sources directly
project.yml               # xcodegen spec
```
