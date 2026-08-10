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
      final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;

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
  /// Returns `true` if the install intent was launched successfully.
  Future<bool> downloadAndInstall(String url) async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file = File('${dir.path}/update.apk');

      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        return false;
      }

      await file.writeAsBytes(response.bodyBytes);

      final result = await _channel.invokeMethod<bool>('installApk', {
        'path': file.path,
      });
      return result ?? false;
    } on Exception {
      return false;
    }
  }

  /// Strip the build number suffix from a pubspec version string.
  /// "0.1.0+1" → "0.1.0".
  String stripBuildNumber(String version) {
    final idx = version.indexOf('+');
    return idx >= 0 ? version.substring(0, idx) : version;
  }

  /// Return true if [a] is a newer semver than [b].
  bool isNewer(String a, String b) {
    try {
      final aParts = a.split('.').map(int.parse).toList();
      final bParts = b.split('.').map(int.parse).toList();
      for (var i = 0; i < 3; i++) {
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
