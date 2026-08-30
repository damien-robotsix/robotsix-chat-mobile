# Changelog

## [0.3.0](https://github.com/damien-robotsix/robotsix-chat-mobile/compare/robotsix_chat_mobile-v0.2.0...robotsix_chat_mobile-v0.3.0) (2026-08-30)


### Features

* Add CI build job producing an installable Android APK + documented run instructions (20260809T110803Z-add-ci-build-job-producing-an-installabl-82d8) ([#7](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/7)) ([236d95a](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/236d95a129df0bedbde6c607e9e67047858ad8fe))
* completeness_check scan: 2 findings (2026-08-09) (20260809T193150Z-completeness-check-scan-2-findings-2026-9f4e) ([#12](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/12)) ([ada8f8f](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/ada8f8f6ba5f54fed6dbeb1657e4829f6cc29640))
* health scan: 3 findings (2026-08-23) (20260823T205958Z-health-scan-3-findings-2026-08-23-9ae5) ([#37](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/37)) ([c0721bc](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/c0721bcc2abac4af98f2d20f0888ffeea88334da))
* In-app auto-update from GitHub Releases (20260809T123643Z-in-app-auto-update-from-github-releases-37ba) ([#10](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/10)) ([eb0f1e4](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/eb0f1e49fdaacab2ee90acf1c59e483e2e4a2831))
* Make UpdateService testable by injecting http.Client and adding unit tests (20260809T201458Z-make-updateservice-testable-by-injecting-d203) ([#18](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/18)) ([931c89e](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/931c89e87b9b343dcd9e803b01937834adb6bb12))
* Real implementation: mobile app reflects chat-agent capabilities over the real SSE channel with fleet mobile-token-exchange auth (20260809T125313Z-real-implementation-mobile-app-reflects-774a) ([#13](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/13)) ([cdd10ee](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/cdd10eec4e81d372f7bea7ac3a44d61563c716e7))
* Resolve OIDC TODO in auth_provider.dart (backend endpoint now built) (20260821T090942Z-resolve-oidc-todo-in-auth-provider-dart-4a05) ([#26](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/26)) ([0b97ce1](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/0b97ce1af2981e309264d224d7fee95a870b9062))
* robotsix-chat-mobile: Build out ApiService from stubs (real HTTP, SSE streaming, auth) (20260809T034201Z-robotsix-chat-mobile-build-out-apiservic-7624) ([#6](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/6)) ([51d2018](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/51d2018c6a0512c33b03b31f5670b1ef7b88ee47))
* Wire session CRUD methods into UI — session list screen or ChatScreen session management (20260824T202703Z-wire-session-crud-methods-into-ui-sessio-f636) ([#42](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/42)) ([d4f2255](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/d4f2255c2d84c9f10df426cf14592c0af0b0667f))


### Bug Fixes

* API token stored unencrypted in SharedPreferences — use flutter_secure_storage (20260809T193743Z-api-token-stored-unencrypted-in-sharedpr-7325) ([#14](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/14)) ([21dc773](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/21dc773b487c448e5acb1f93003c04c85d555c78))
* Establish a coherent Flutter/Dart + Android toolchain baseline (pin package_info_plus ^9.x, align compileSdk/AGP/Kotlin) (20260824T140546Z-establish-a-coherent-flutter-dart-androi-cce9) ([#40](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/40)) ([8afe413](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/8afe4135f00c5c01a5d21dde15dc7efd99dcc9f2))
* Fix Android build broken by shared_preferences_android 2.4.23 / Kotlin Gradle Plugin incompatibility (20260821T113338Z-fix-android-build-broken-by-shared-prefe-8d2a) ([#30](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/30)) ([414c48b](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/414c48ba32a08b249ff68e7246529d4cf6b924b4))
* In-app update Install button fails silently: await the flow, show progress, surface errors, handle install-unknown-apps permission (20260829T212654Z-in-app-update-install-button-fails-silen-e70d) ([#48](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/48)) ([227dae9](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/227dae99d0482da7b7219ae89892b5cb7601344b))
* Resolve Flutter/Dart CI version mismatch: package_info_plus ^10.2.1 cannot resolve under Flutter 3.24 (20260824T121909Z-resolve-flutter-dart-ci-version-mismatch-f2c4) ([#39](https://github.com/damien-robotsix/robotsix-chat-mobile/issues/39)) ([d566f18](https://github.com/damien-robotsix/robotsix-chat-mobile/commit/d566f181030c72f99a03dc0c426b1dab50b44cd4))
