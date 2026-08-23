# robotsix-chat-mobile

Mobile client for [robotsix-chat](https://github.com/damien-robotsix/robotsix-chat) — a conversational agent service.

This repository follows the [robotsix-standards](https://github.com/damien-robotsix/robotsix-standards). This app provides a cross-platform mobile interface for chatting with agents and receiving push-style notifications via SSE (Server-Sent Events).

## Framework choice: Flutter

Flutter was chosen over React Native for this project because:

- **Single codebase, true native compilation** — Dart compiles to ARM native code, avoiding the JavaScript bridge overhead that can cause jank during SSE stream processing.
- **Rich built-in widget library** — Material Design widgets out of the box for chat UI (lists, text fields, cards) without third-party dependencies.
- **Strong async/stream support** — Dart's `Stream` and `async`/`await` map naturally to SSE event streams, and the `http` package provides a clean client.
- **Mature CI/CD** — `flutter analyze`, `flutter test`, and `flutter build` integrate cleanly into GitHub Actions.
- **Single developer velocity** — One language (Dart), one framework, fast hot-reload, consistent tooling across platforms.

## Project structure

```
lib/
  main.dart                  # App entry point, routing
  screens/
    chat_screen.dart         # Chat UI placeholder
    settings_screen.dart     # Backend URL / credential config
  models/
    chat_message.dart        # Message data model
  services/
    api_service.dart         # HTTP + SSE client with token auth
test/
  widget_test.dart           # Smoke test
```

## Documentation

No documentation site exists for this repository yet. For now, see the [robotsix-standards](https://github.com/damien-robotsix/robotsix-standards) for cross-cutting conventions and this README for project-specific instructions.

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.24
- Android SDK / Xcode (for platform builds)
- A device or emulator

### Setup

```bash
git clone https://github.com/damien-robotsix/robotsix-chat-mobile.git
cd robotsix-chat-mobile
flutter pub get
```

### Run

```bash
# Launch on a connected device / emulator
flutter run
```

### Test & lint

```bash
flutter test
flutter analyze
```

## Configuration

The Settings screen (gear icon on the chat screen) lets you configure:

- **Backend Base URL** — the robotsix-chat server endpoint (e.g. `https://chat.example.com`)

### Authentication (SSO / tinyauth)

Authentication uses the fleet SSO (tinyauth) flow:

1. Open **Settings** (gear icon) and enter your **Backend Base URL**.
2. Tap **Log in with SSO** — this opens the tinyauth login page in your browser.
3. Complete the login. The browser redirects back to the app automatically.
4. The app stores your credentials securely in the platform keychain (`flutter_secure_storage`) and attaches a short-lived Bearer token to every API request.

To log out, tap **Log out** in Settings.

## Installing the CI APK

Every push and PR to `main` produces a debug APK via GitHub Actions. To install it:

1. Open the [Actions](https://github.com/damien-robotsix/robotsix-chat-mobile/actions) tab.
2. Select the workflow run for your branch / PR.
3. Scroll to **Artifacts** and download `app-debug`.
4. Unzip and sideload the `.apk` onto your Android device, or drag it onto a running emulator:

   ```bash
   adb install app-debug.apk
   ```

> **Note:** The CI build uses `--debug` (unsigned). Release builds require signing keys that are not stored in this repository.

## In-app auto-update (Android)

The app checks for updates on startup and from the Settings screen. When a newer version is available:

1. A dialog appears showing the new version and offering a one-tap install.
2. Tap **Install** — the app downloads the signed APK from the latest [GitHub Release](https://github.com/damien-robotsix/robotsix-chat-mobile/releases) and opens the Android package installer.
3. Confirm the install — the new version replaces the existing one (data is preserved).

### First-time manual install

The auto-update mechanism requires an initial manual sideload — install the APK once via `adb install` or by downloading it from a web browser. After that, future updates are offered in-app.

> **Important:** Android requires that every release APK be signed with the **same signing key**. If the key changes, the in-app update will fail with a signature-mismatch error. The signing key is stored as a GitHub Actions secret and is not committed to the repository.

### Operator provisioning

The following GitHub Actions secrets must be configured for the release workflow:

| Secret | Description |
|---|---|
| `KEYSTORE_BASE64` | Base64-encoded JKS/PKCS12 keystore file |
| `KEYSTORE_PASSWORD` | Password for the keystore |
| `KEY_ALIAS` | Alias of the signing key within the keystore |
| `KEY_PASSWORD` | Password for the signing key |

To generate a keystore for the first time:

```bash
keytool -genkey -v -keystore release.keystore -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <password> -keypass <password> \
  -dname "CN=robotsix-chat-mobile"
```

Then encode it and add the secrets:

```bash
base64 -w0 release.keystore  # use this as KEYSTORE_BASE64
```

## Manual smoke test

After installing the APK and pointing it at a live robotsix-chat backend:

1. **Configure the backend** — open Settings (gear icon), enter the **Backend Base URL** for your robotsix-chat instance.
2. **Log in** — tap **Log in with SSO**, complete the fleet SSO login in your browser, and wait for the app to capture the redirect.
3. **Open a chat** — return to the chat screen; open the drawer (hamburger menu) to see your sessions. Create a new session or select an existing one.
4. **Send a message** — type a message and tap send. The message should appear in the chat history.
5. **Receive an SSE response** — the agent's reply should stream back in real time as the response arrives.
6. **Session management** — use the drawer to switch between sessions, close completed sessions, or delete unwanted ones.

## License

MIT — see [LICENSE](LICENSE).
