# gowi — Get On With It

A lightweight macOS menu bar + window app that shows open pull requests across a user-configured list of GitHub repositories. Read-only; clicking a PR opens it in the browser.

See `pr-tracker-spec.md` for the full product + technical spec and `TASKS.md` for the commit-sized task breakdown.

## Status

Pre-v1 proof of concept. The PoC builds a window-only, device-flow, single-repo-fetch version against real GitHub. Menu bar, cache, and polish come in subsequent milestones.

## Building

During the PoC the project is a plain Swift Package so it builds with the command-line toolchain:

```
swift build
swift run gowi
```

Once Xcode is installed, the same `Sources/` tree is intended to drop into an Xcode project (see `TASKS.md` task #1). Sandboxing, entitlements, and signing live in the Xcode project — the SPM build is unsandboxed and intended for local development only.

## First-run setup

1. Register a GitHub OAuth app at <https://github.com/settings/applications/new>. Enable "Device Flow".
2. Copy the Client ID into `Sources/Gowi/Config.swift` (replace the `GITHUB_CLIENT_ID_TODO` placeholder).
3. `swift run gowi`, click "Sign in with GitHub", follow the device-flow prompt in your browser.
4. Open Settings → Repositories, add `owner/name` entries to track.

## Layout

```
Sources/Gowi/
├── Config.swift              # OAuth client ID constant
├── GowiApp.swift             # App entry point (scenes)
├── AppModel.swift            # Observable root state
├── Models/                   # PullRequest, TrackedRepo, enums
├── Auth/                     # KeychainHelper, DeviceFlowClient, AuthService
├── Net/                      # GraphQL client + queries
├── Settings/                 # RepoStore (UserDefaults-backed)
└── UI/                       # Views
```
