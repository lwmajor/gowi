# Releasing gowi

## Prerequisites (one-time setup)

1. **Developer ID signing identity** — enroll in the Apple Developer Program and request a
   "Developer ID Application" certificate via Xcode → Settings → Accounts.

2. **Notarization credentials** — create an app-specific password at
   <https://appleid.apple.com> (Security → App-Specific Passwords). You'll need:
   - `APPLE_ID` — your Apple ID email
   - `APPLE_TEAM_ID` — your 10-character Team ID (visible in Xcode or developer.apple.com)
   - `APPLE_APP_PASSWORD` — the app-specific password
   - `DEVELOPER_ID` — your signing identity string, e.g.
     `"Developer ID Application: Lloyd Major (XXXXXXXXXX)"`
     (run `security find-identity -v -p codesigning` to see your identities)

3. **Sparkle EdDSA keypair** — generated once; the private key must never be committed.

   a. Open the project in Xcode to let SPM fetch Sparkle.
   b. Run the key generator:
      ```
      .build/checkouts/Sparkle/bin/generate_keys
      ```
   c. Copy the **public key** into `App/Info.plist` → `SUPublicEDKey`.
   d. Store the **private key** somewhere safe (1Password, etc.). You will need it
      to sign every release DMG.

## Releasing a new version

### 1. Bump the version

In `project.yml`, update:
```yaml
MARKETING_VERSION: "x.y.z"   # human-readable version shown in About and Sparkle
CURRENT_PROJECT_VERSION: "N" # monotonically increasing integer build number
```

Commit: `dist: bump version to x.y.z`

### 2. Build and notarize the DMG

Export the credentials as env vars, then run:
```sh
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="XXXXXXXXXX"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)"

scripts/build-dmg.sh
```

The script regenerates the Xcode project, builds a Release binary, notarizes the `.app`,
packages it into a signed DMG, and prints the path. Output lands in `build/`.

### 3. Sign the DMG for Sparkle

```sh
.build/checkouts/Sparkle/bin/sign_update build/gowi-x.y.z.dmg
```

This prints a `sparkle:edSignature` value and the file length in bytes.

### 4. Update appcast.xml

Edit `App/appcast.xml` — add a new `<item>` block at the top of the channel (above the
previous release) with the correct version, pub date, DMG URL, length, and signature:

```xml
<item>
  <title>Version x.y.z</title>
  <pubDate>Www, DD Mon YYYY HH:MM:SS +0000</pubDate>
  <sparkle:version>N</sparkle:version>
  <sparkle:shortVersionString>x.y.z</sparkle:shortVersionString>
  <enclosure
    url="https://github.com/lwmajor/gowi/releases/download/vx.y.z/gowi-x.y.z.dmg"
    length="FILESIZE"
    type="application/octet-stream"
    sparkle:edSignature="SIGNATURE"
  />
</item>
```

Commit: `dist: appcast for x.y.z`

### 5. Tag and push

```sh
git tag -s vx.y.z -m "vx.y.z"
git push origin main --tags
```

### 6. Create the GitHub release

```sh
gh release create vx.y.z build/gowi-x.y.z.dmg App/appcast.xml \
  --title "gowi vx.y.z" \
  --notes-file CHANGELOG.md
```

For an alpha / beta / RC, mark the GitHub release as a pre-release. Apple requires
`CFBundleShortVersionString` to be three numeric components, so the pre-release
designation lives in the GitHub release (and in `CHANGELOG.md`), not in the in-app
version string:

```sh
gh release create v0.1.0 build/gowi-0.1.0.dmg App/appcast.xml \
  --title "gowi v0.1.0 (alpha)" \
  --notes-file CHANGELOG.md \
  --prerelease
```

Sparkle reads the appcast from:
`https://github.com/lwmajor/gowi/releases/latest/download/appcast.xml`

Uploading `appcast.xml` to each release and tagging it as `latest` satisfies this URL.
Note: GitHub treats the most recent non-prerelease as `latest`. While only pre-releases
exist, manually mark the desired release as `latest` (or add `--latest` to
`gh release create`) so Sparkle clients can find the appcast.
