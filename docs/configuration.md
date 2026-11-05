# Configuration reference

All persistent configuration keys used by the app, their types, storage
backends, and default values.

| Key            | Type   | Storage backend        | Default          | Description                                      |
|----------------|--------|------------------------|------------------|--------------------------------------------------|
| `api_base_url` | String | `SharedPreferences`    | _(none)_         | Base URL of the robotsix-chat backend (e.g. `https://chat.example.com`). Configured via the Settings screen. |
| `oidc_subject_token` | String | `FlutterSecureStorage` | _(none)_   | Persisted SSO (OIDC) subject token, saved after the SSO login flow and used by `OidcTokenExchangeAuthProvider` to acquire short-lived Bearer tokens. Stored encrypted; cleared on log-out. |
| `owner_id`     | String | `SharedPreferences`    | Auto-generated   | Stable 16-character per-install client identifier. Sent with every chat request so the backend can associate sessions with this device. Generated once on first launch. |

## How to change settings

All configurable values are set via the **Settings** screen (gear icon
on the chat screen):

- **Backend Base URL** — stored under `api_base_url`.
- **Log in with SSO** — launches the fleet SSO login flow; the resulting
  subject token is stored under `oidc_subject_token`. **Log out** removes it.

Settings take effect on the next `ApiService` instantiation. The
`ChatScreen` lazily initialises its `ApiService` on the first message
send, so changing the URL or token and returning to the chat screen
will pick up the new values automatically.