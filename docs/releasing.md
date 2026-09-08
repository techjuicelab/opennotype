# macOS release packaging

The scripts support Apple Silicon builds. A development bundle is not a notarized public release. Developer ID signing, Apple notarization, Gatekeeper acceptance on another Mac, and an update from a previous installed version still require real release validation.

## Development build

Run `./scripts/build-app.sh`. It creates `build/OpenNoType.app` with an ad-hoc signature by default. `DEVELOPMENT_SIGNING_IDENTITY` may select an existing local development identity. The script signs each Sparkle helper separately and keeps Downloader's own entitlements; it does not use deep signing or request a timestamp for development.

## Public update settings

To embed an existing update channel, set both of these environment variables before building:

- `SPARKLE_FEED_URL`: the HTTPS URL of the production Sparkle appcast.
- `SPARKLE_PUBLIC_ED_KEY`: the matching base64-encoded, 32-byte Ed25519 **public** key.

The settings are written only into the built app's Info.plist, before code signing. Invalid or incomplete settings stop the build. With neither set, the development source configuration keeps updates inactive. Never supply or commit a private update-signing key. Merely setting these variables does not create or publish an appcast.

## Distribution package

Update `CFBundleShortVersionString` and the monotonically increasing `CFBundleVersion` in `Resources/Info.plist` for each release. Set `DEVELOPER_ID_APPLICATION` to an existing `Developer ID Application: …` identity and `NOTARY_PROFILE` to an existing `notarytool` Keychain profile. Credentials are configured outside this repository; the scripts neither create nor export them.

Running `./scripts/package-release.sh` performs actual signing and submits the app and DMG to Apple's notarization service. It signs Sparkle's Installer, Downloader, Autoupdate, Updater, and framework in that order with Developer ID, Hardened Runtime, and secure timestamps, then signs the containing app with its own entitlements. Downloader alone preserves its original entitlements, following the [Sparkle signing guide](https://sparkle-project.org/documentation/sandboxing/#code-signing).

Successful packaging leaves a ZIP containing the stapled app and a signed, stapled DMG plus its SHA-256 file in `dist/`. The script verifies code signatures, validates the stapled tickets, and assesses the app with Gatekeeper. These steps run only when the release script is explicitly invoked with credentials; the CI workflow creates a development artifact.

Release upload, Sparkle EdDSA archive signing, appcast generation, and hosting are separate operations and are not automated here. Before publishing, confirm the archive signature with the matching public key, the appcast's version and archive URL, clean installation on another Mac, and an actual upgrade from the previous version. The packaging script has not yet been exercised with production signing/notarization credentials.
