# Security Policy

## Reporting a Vulnerability
Please report security vulnerabilities privately by email to admin@robotsix.net.
Do not open a public issue for security problems.

## Android Backup Policy
The Android app sets `android:allowBackup="false"` in
`android/app/src/main/AndroidManifest.xml`, so Android Auto Backup does not
copy app data to Google Drive. That data includes the server URL and owner id
in `shared_preferences` and the `flutter_secure_storage` file that holds the
auth token. The secure-storage file is encrypted with an Android Keystore key,
and that key is never backed up. A restored copy of the file could therefore
not be decrypted, and reading it can fail. On a new device or after a
reinstall, the user enters the server settings again and signs in again.

## Response Time
This project is maintained by a single person and cannot guarantee a response
time. Reports are handled on a best-effort basis.

## Coordinated Disclosure
This project follows coordinated disclosure: please allow a reasonable window
to release a fix before any public disclosure.
