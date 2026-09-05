import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

/// Result of an update check.
enum UpdateStatus {
  /// No update available — current version is up to date.
  upToDate,

  /// A newer version is available.
  updateAvailable,

  /// The check failed (network error, API error, etc.).
  error,
}

/// The outcome of an update check, including version strings on success.
class UpdateCheckResult {
  final UpdateStatus status;
  final String? currentVersion;
  final String? latestVersion;
  final String? apkDownloadUrl;
  final String? errorMessage;

  const UpdateCheckResult({
    required this.status,
    this.currentVersion,
    this.latestVersion,
    this.apkDownloadUrl,
    this.errorMessage,
  });

  factory UpdateCheckResult.upToDate(String current) => UpdateCheckResult(
        status: UpdateStatus.upToDate,
        currentVersion: current,
      );

  factory UpdateCheckResult.available({
    required String current,
    required String latest,
    required String downloadUrl,
  }) =>
      UpdateCheckResult(
        status: UpdateStatus.updateAvailable,
        currentVersion: current,
        latestVersion: latest,
        apkDownloadUrl: downloadUrl,
      );

  factory UpdateCheckResult.error(String msg) => UpdateCheckResult(
        status: UpdateStatus.error,
        errorMessage: msg,
      );
}

/// The kind of failure that occurred while downloading or installing an
/// update, used to give the user actionable feedback.
enum InstallErrorKind {
  /// The APK could not be downloaded (network error or non-200 response).
  downloadFailed,

  /// The user has not granted the "install unknown apps" permission and
  /// must do so before the install can proceed.
  permissionRequired,

  /// The installed build predates the native install handler
  /// (a [MissingPluginException] was raised).
  pluginMissing,

  /// The native side reported a platform error while launching the
  /// installer.
  platformError,
}

/// Raised by [UpdateService.downloadAndInstall] when the download or the
/// native install step fails.  Carries a [kind] so callers can tailor the
/// message shown to the user, plus a human-readable [message].
class InstallException implements Exception {
  /// The category of failure.
  final InstallErrorKind kind;

  /// A user-facing description of what went wrong.
  final String message;

  /// Creates an [InstallException].
  const InstallException(this.kind, this.message);

  @override
  String toString() => 'InstallException($kind): $message';
}

/// Service that checks GitHub Releases for newer app versions and
/// downloads + installs APKs.
class UpdateService {
  static const _repoOwner = 'damien-robotsix';
  static const _repoName = 'robotsix-chat-mobile';
  static const _channel = MethodChannel('com.robotsix.chat_mobile/install');

  final http.Client _client;

  /// Creates an [UpdateService].
  ///
  /// The optional [client] parameter allows injecting a custom
  /// [http.Client] for testing.  When omitted the default
  /// [http.Client] is used.
  UpdateService({http.Client? client})
      : _client = client ?? http.Client();

  /// Check GitHub Releases for a newer version than [currentVersion].
  ///
  /// [currentVersion] should be the semver portion of the app version
  /// (e.g. "0.1.0" from pubspec "0.1.0+1").
  Future<UpdateCheckResult> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = stripBuildNumber(info.version);

    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'robotsix-chat-mobile',
        },
      );

      if (response.statusCode != 200) {
        return UpdateCheckResult.error(
          'GitHub API returned ${response.statusCode}',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String? ?? '';
      final latestVersion = extractSemver(tag);

      // Find the APK asset.
      final assets = body['assets'] as List<dynamic>? ?? [];
      String? apkUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (apkUrl == null) {
        return UpdateCheckResult.error('No APK asset found in latest release');
      }

      if (isNewer(latestVersion, current)) {
        return UpdateCheckResult.available(
          current: current,
          latest: latestVersion,
          downloadUrl: apkUrl,
        );
      }

      return UpdateCheckResult.upToDate(current);
    } on SocketException {
      return UpdateCheckResult.error('Network unavailable');
    } on http.ClientException {
      return UpdateCheckResult.error('Network error');
    } on FormatException {
      return UpdateCheckResult.error('Invalid API response');
    }
  }

  /// Download the APK from [url] and launch the system installer.
  ///
  /// Completes normally once the system installer has been launched.
  /// Throws an [InstallException] (with a specific [InstallErrorKind])
  /// when the download fails, the install permission is missing, the
  /// native install handler is unavailable, or the platform reports an
  /// error — so callers can surface an actionable message to the user.
  /// Failures are never swallowed silently.
  Future<void> downloadAndInstall(String url) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/update.apk');

    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url));
    } on SocketException catch (e) {
      throw InstallException(
        InstallErrorKind.downloadFailed,
        'Download failed: network unavailable (${e.message}).',
      );
    } on http.ClientException catch (e) {
      throw InstallException(
        InstallErrorKind.downloadFailed,
        'Download failed: ${e.message}',
      );
    }

    if (response.statusCode != 200) {
      throw InstallException(
        InstallErrorKind.downloadFailed,
        'Download failed: server returned ${response.statusCode}.',
      );
    }

    await file.writeAsBytes(response.bodyBytes);

    try {
      final ok = await _channel.invokeMethod<bool>('installApk', {
        'path': file.path,
      });
      if (ok != true) {
        throw const InstallException(
          InstallErrorKind.platformError,
          'The system installer could not be launched.',
        );
      }
    } on MissingPluginException {
      throw const InstallException(
        InstallErrorKind.pluginMissing,
        'This installed build does not support in-app updates. '
        'Please download and install the new version manually.',
      );
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_REQUIRED') {
        throw const InstallException(
          InstallErrorKind.permissionRequired,
          'Permission required: allow installing unknown apps for this '
          'app in the settings screen that just opened, then tap Install '
          'again.',
        );
      }
      throw InstallException(
        InstallErrorKind.platformError,
        'Install failed: ${e.message ?? e.code}',
      );
    }
  }

  /// Strip the build number suffix from a pubspec version string.
  /// "0.1.0+1" → "0.1.0".
  String stripBuildNumber(String version) {
    final idx = version.indexOf('+');
    return idx >= 0 ? version.substring(0, idx) : version;
  }

  /// Extract the X.Y.Z semver portion from a release tag, independent of
  /// any prefix.
  ///
  /// release-please prefixes tags with the package name
  /// (e.g. "robotsix_chat_mobile-v0.3.3"); GitHub Releases may also use a
  /// plain "v0.3.3" or bare "0.3.3".  Returns the matched "X.Y.Z" string,
  /// or an empty string when the tag contains no semver (in which case
  /// [isNewer] safely returns false and the app reports up-to-date).
  String extractSemver(String tag) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tag);
    return match?.group(1) ?? '';
  }

  /// Return true if [a] is a newer semver than [b].
  bool isNewer(String a, String b) {
    try {
      final aParts = a.split('.').map(int.parse).toList();
      final bParts = b.split('.').map(int.parse).toList();
      final maxParts =
          aParts.length > bParts.length ? aParts.length : bParts.length;
      for (var i = 0; i < maxParts; i++) {
        final av = i < aParts.length ? aParts[i] : 0;
        final bv = i < bParts.length ? bParts[i] : 0;
        if (av > bv) return true;
        if (av < bv) return false;
      }
      return false;
    } on FormatException {
      return false;
    }
  }
}
