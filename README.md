# robotsix-chat-mobile

Mobile client for [robotsix-chat](https://github.com/damien-robotsix/robotsix-chat) — a conversational agent service. This app provides a cross-platform mobile interface for chatting with agents and receiving push-style notifications via SSE (Server-Sent Events).

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
    api_service.dart         # Stub API service (TODO: real backend)
test/
  widget_test.dart           # Smoke test
```

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
- **API Key / Token** — authentication credential for the chat backend

These are stored locally on-device (currently in-memory; persistent storage TBD).

## License

MIT — see [LICENSE](LICENSE).
