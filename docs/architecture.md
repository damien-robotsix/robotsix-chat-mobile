# Architecture

This document describes the architecture of `robotsix-chat-mobile`, the
Flutter-based mobile client for the
[robotsix-chat](https://github.com/damien-robotsix/robotsix-chat) backend.

## High-level component diagram

```
┌─────────────────────────────────────────────┐
│                   main.dart                  │
│  Entry point, route registration, theming   │
└──────────┬─────────────────────┬────────────┘
           │                     │
           ▼                     ▼
┌──────────────────┐   ┌──────────────────────┐
│   ChatScreen     │   │   SettingsScreen     │
│  (chat_screen)   │   │ (settings_screen)    │
│                  │   │                      │
│ - Message list   │   │ - Backend URL config │
│ - SSE streaming  │   │ - API token config   │
│ - Send button    │   │ - Update check       │
└────────┬─────────┘   └──────────┬───────────┘
         │                        │
         ▼                        ▼
┌─────────────────────────────────────────────────┐
│                  ApiService                      │
│              (api_service.dart)                  │
│                                                  │
│  - POST /chat       (SSE stream)                │
│  - GET  /sessions   (list)                      │
│  - POST /sessions   (create)                    │
│  - DELETE /sessions/{id}                        │
│  - POST /sessions/{id}/close                    │
│  - GET  /history    (transcript)               │
│                                                  │
│  ┌───────────────────────────┐                  │
│  │  AuthProvider (interface) │                  │
│  │  ┌─────────────────────┐  │                  │
│  │  │ OidcTokenExchange   │  │                  │
│  │  │ AuthProvider        │  │                  │
│  │  └─────────────────────┘  │                  │
│  └───────────────────────────┘                  │
└────────┬──────────────────────┬─────────────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐   ┌──────────────────────────┐
│ SharedPreferences│   │ FlutterSecureStorage     │
│                  │   │                          │
│ - api_base_url   │   │ - api_token (encrypted)  │
│ - owner_id       │   │                          │
└─────────────────┘   └──────────────────────────┘
```

## Data flow: sending a message

1. **App start** — `main.dart` creates a `MaterialApp` with routes for
   `/` (ChatScreen) and `/settings` (SettingsScreen).

2. **ChatScreen initialisation** — `_ChatScreenState.initState()` calls
   `_initApiService()`, which calls `ApiService.fromStorage()`. This reads
   the saved `api_base_url` and `api_token` from local storage and
   constructs an `ApiService` with an `OidcTokenExchangeAuthProvider`.
   If no base URL is configured, a `StateError` is silently caught and
   `_apiService` remains `null`.

3. **User sends a message** — `_sendMessage()` is triggered:
   - The input field is validated and cleared.
   - A user `ChatMessage` is appended to the message list.
   - An empty agent `ChatMessage` placeholder is appended.
   - `ApiService.fromStorage()` is called lazily if `_apiService` is null.
   - `apiService.sendMessage()` is called, returning a `Stream<ChatEvent>`.

4. **SSE stream processing** — `_subscribeToStream()` listens on the
   returned stream:
   - **TokenEvent** → appends content to the agent placeholder message
     via `_appendToMessage()`.
   - **DoneEvent** → records the `sessionId` for subsequent messages,
     clears the loading state.
   - **ErrorEvent** → displays the backend error message via
     `_handleStreamError()`.

5. **Error handling** — `_handleStreamError()` updates the agent message
   with the error text, clears the loading state, and nulls out the
   active stream subscription. This single method is shared across all
   five error paths (stream `ErrorEvent`, stream `onError`, `ApiException`,
   `StateError`, and generic exceptions).

## Authentication flow

1. The `OidcTokenExchangeAuthProvider` holds an OIDC credential
   (`subjectToken`) retrieved from secure storage.

2. Before every outgoing HTTP request, `requestHeaders()` is called:
   - If a cached access token is still valid (within `expires_in` minus
     a one-minute clock-skew margin), it is returned immediately.
   - Otherwise, the `subjectToken` is exchanged at
     `POST /chat/auth/mobile-token` for a short-lived Bearer token,
     which is cached in memory.

3. The returned `Authorization: Bearer <token>` header is attached to
   every request.

## Persistent storage

| Data          | Backend              | Encrypted |
|---------------|----------------------|-----------|
| `api_base_url`| SharedPreferences    | No        |
| `owner_id`    | SharedPreferences    | No        |
| `api_token`   | FlutterSecureStorage | Yes       |

The `owner_id` is a 16-character random alphanumeric string generated
on first launch and persisted permanently.

## In-app update mechanism

Refer to [docs/auto-update.md](auto-update.md) for the auto-update
flow and operator provisioning details.