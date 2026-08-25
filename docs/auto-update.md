# In-app auto-update (Android)

The app checks for updates on startup and from the Settings screen. When a
newer version is available:

1. A dialog appears showing the new version and offering a one-tap install.
2. Tap **Install** — the app downloads the signed APK from the latest
   [GitHub Release](https://github.com/damien-robotsix/robotsix-chat-mobile/releases)
   and opens the Android package installer.
3. Confirm the install — the new version replaces the existing one (data is
   preserved).

## First-time manual install

The auto-update mechanism requires an initial manual sideload — install the
APK once via `adb install` or by downloading it from a web browser. After
that, future updates are offered in-app.

> **Important:** Android requires that every release APK be signed with the
> **same signing key**. If the key changes, the in-app update will fail with a
> signature-mismatch error. The signing key is stored as a GitHub Actions
> secret and is not committed to the repository.

## Operator provisioning

The following GitHub Actions secrets must be configured for the release
workflow:

| Secret              | Description                                   |
|---------------------|-----------------------------------------------|
| `KEYSTORE_BASE64`   | Base64-encoded JKS/PKCS12 keystore file       |
| `KEYSTORE_PASSWORD` | Password for the keystore                     |
| `KEY_ALIAS`         | Alias of the signing key within the keystore  |
| `KEY_PASSWORD`      | Password for the signing key                  |

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