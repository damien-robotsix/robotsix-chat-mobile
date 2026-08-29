# Release process

Releases are fully automated with the fleet's shared
[release-please](https://github.com/googleapis/release-please) workflow. There is
no manual version editing and no hand-rolled version-grepping release job.

## How it works

1. **Conventional commits land on `main`.** `feat:` commits bump the minor
   version, `fix:` commits bump the patch version, and a `!`/`BREAKING CHANGE`
   footer bumps the major version.
2. **release-please opens/updates a release PR.** The caller workflow
   [`.github/workflows/release-please.yml`](../.github/workflows/release-please.yml)
   delegates to
   `damien-robotsix/robotsix-github-workflows/.github/workflows/release-please.yml`
   (SHA-pinned). release-please accumulates the pending changes into a release PR
   that bumps the version in `pubspec.yaml` and updates `CHANGELOG.md`.
3. **Merging the release PR tags and publishes.** On merge, release-please
   creates the `v{version}` tag and a matching GitHub Release. Because the shared
   workflow authenticates with a GitHub App installation token (not the default
   `GITHUB_TOKEN`), the `release` event fires and triggers downstream workflows.
4. **The signed APK is built and attached.**
   [`.github/workflows/release-apk.yml`](../.github/workflows/release-apk.yml)
   runs on `release: published`, builds the signed release APK, and uploads
   `app-release.apk` as the release's single `*.apk` asset.

## Version and build-number handling

`pubspec.yaml` uses Flutter's `version: <semver>+<buildNumber>` format.

- **The semver portion is owned by release-please**, configured via
  [`release-please-config.json`](../release-please-config.json) with the `dart`
  release type (which manages the `version:` field in `pubspec.yaml`). The
  current version is tracked in
  [`.release-please-manifest.json`](../.release-please-manifest.json).
- **The Android build number (`versionCode`) is injected at release-build time**
  from the monotonically increasing CI run number
  (`flutter build apk --build-number=${{ github.run_number }}` in
  `release-apk.yml`). This keeps the `versionCode` strictly increasing across
  releases — so a newer APK always installs cleanly as an upgrade — without
  requiring release-please to manage build metadata in `pubspec.yaml`.

## Updater contract

The in-app updater (`UpdateService.checkForUpdate()`, see
[auto-update.md](auto-update.md)) reads the repository's *latest* GitHub Release,
strips the leading `v` from `tag_name` to obtain the semver, and downloads the
first asset whose name ends in `.apk`. The automated flow preserves this
contract: every release is tagged `v{semver}` and carries exactly one `*.apk`
asset.

## Fleet pitfall: do not skip labeling

The caller workflow does **not** pass `skip-labeling: true`. release-please
relies on the `autorelease: pending` label to detect merged-but-untagged
releases; skipping labeling previously broke tagging in `robotsix-file-hub`.
