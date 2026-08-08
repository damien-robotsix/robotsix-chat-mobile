# Roadmap

This document tracks planned work beyond the initial skeleton.

## 1. Backend API integration

- Replace the stub `ApiService` with real HTTP calls to the robotsix-chat backend.
- Implement the chat message send/receive protocol.
- Handle authentication token refresh.

## 2. SSE streaming

- Connect to the chat backend's Server-Sent Events endpoint for real-time agent message streaming.
- Render streaming responses incrementally in the chat UI (token-by-token display).
- Handle SSE reconnection with exponential backoff.

## 3. Push notifications

- Integrate `firebase_messaging` (or platform equivalent) for `notify_user` push notifications.
- Handle notification routing: tap → open the relevant chat screen.
- Background notification handling.

## 4. Persistent storage

- Store chat history locally (SQLite via `sqflite` or `drift`).
- Persist settings (backend URL, credentials) securely (flutter_secure_storage).
- Offline message queue.

## 5. App-store packaging

- Android: Play Store listing, signing, release builds.
- iOS: App Store Connect, code signing, TestFlight distribution.
- CI/CD pipeline for automated builds and deployment.

## 6. Polish

- Dark mode support.
- Accessibility (semantics, screen-reader labels).
- Internationalization (i18n).
- Error handling and retry UX.
