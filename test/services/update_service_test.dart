import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:robotsix_chat_mobile/services/update_service.dart';

/// Build a JSON body for a GitHub Releases API response.
String _releaseJson(String tag, String apkUrl) {
  return jsonEncode({
    'tag_name': tag,
    'assets': [
      {
        'name': 'app-release.apk',
        'browser_download_url': apkUrl,
      }
    ],
  });
}

/// Run [body] inside `http.runWithClient` with a mock that returns
/// [statusCode] and [responseBody] for every request.
Future<T> _withMockClient<T>(
  Future<T> Function() body,
  int statusCode,
  String responseBody,
) {
  final client = MockClient((request) async {
    return http.Response(responseBody, statusCode);
  });
  return http.runWithClient(body, () => client);
}

void main() {
  // ------------------------------------------------------------------
  // _stripBuildNumber — tested through checkForUpdate with different
  // PackageInfo versions and GitHub tag responses.
  // ------------------------------------------------------------------

  group('stripBuildNumber behaviour', () {
    test('version with "+1" build number is treated as equal to bare version',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0+1',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v0.1.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.upToDate);
    });

    test('version with "+42" build number still compares correctly', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.2.0+42',
        buildNumber: '42',
        buildSignature: '',
      );

      // Latest is older → still upToDate (current is already newer)
      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v0.1.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.upToDate);
    });

    test('version without build number passes through unchanged', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.0.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.upToDate);
    });

    test('version with build number is not falsely equal to different version',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0+99',
        buildNumber: '99',
        buildSignature: '',
      );

      // Latest is different major version.
      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v2.0.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.latestVersion, '2.0.0');
      expect(result.currentVersion, '1.0.0'); // Build stripped
    });

    test('tag without "v" prefix is also handled', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.3.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('0.4.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.latestVersion, '0.4.0');
    });
  });

  // ------------------------------------------------------------------
  // _isNewer — tested through checkForUpdate with varied version pairs.
  // ------------------------------------------------------------------

  group('isNewer behaviour', () {
    test('equal versions are not newer', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.0.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.upToDate);
    });

    test('patch bump is newer', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.0.1', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.latestVersion, '1.0.1');
    });

    test('minor bump is newer', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.1.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.latestVersion, '1.1.0');
    });

    test('major bump is newer', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v2.0.0', 'http://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.latestVersion, '2.0.0');
    });

    test('pre-release tag is not treated as newer (parse failure → not newer)',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.0.0-rc1', 'http://example.com/app.apk'),
      );

      // _isNewer catches FormatException and returns false.
      expect(result.status, UpdateStatus.upToDate);
    });

    test('multi-digit version segments compare numerically', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.9',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.0.10', 'http://example.com/app.apk'),
      );

      // 10 > 9 numerically, not lexicographically.
      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.latestVersion, '1.0.10');
    });
  });

  // ------------------------------------------------------------------
  // checkForUpdate — full scenarios
  // ------------------------------------------------------------------

  group('checkForUpdate', () {
    test('update available — 200 with newer version', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v0.2.0', 'https://example.com/app-release.apk'),
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.currentVersion, '0.1.0');
      expect(result.latestVersion, '0.2.0');
      expect(result.apkDownloadUrl, 'https://example.com/app-release.apk');
    });

    test('no update — 200 with same version', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        200,
        _releaseJson('v1.0.0', 'https://example.com/app.apk'),
      );

      expect(result.status, UpdateStatus.upToDate);
      expect(result.currentVersion, '1.0.0');
    });

    test('error — GitHub API returns 404', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        404,
        '{"message":"Not Found"}',
      );

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('404'));
    });

    test('error — GitHub API returns 500', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final result = await _withMockClient(
        () => UpdateService().checkForUpdate(),
        500,
        'Internal Server Error',
      );

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('500'));
    });

    test('error — no APK asset in release', () async {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v0.2.0',
            'assets': <Map<String, dynamic>>[],
          }),
          200,
        );
      });

      final result = await http.runWithClient(
        () => UpdateService().checkForUpdate(),
        () => client,
      );

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('No APK asset'));
    });
  });

  // ------------------------------------------------------------------
  // downloadAndInstall
  // ------------------------------------------------------------------

  group('downloadAndInstall', () {
    test('returns false on HTTP 404', () async {
      final result = await _withMockClient(
        () => UpdateService().downloadAndInstall('http://example.com/app.apk'),
        404,
        'Not Found',
      );

      expect(result, isFalse);
    });

    test('returns false on network error', () async {
      // Use a closed port on localhost to trigger a connection error.
      final result = await UpdateService().downloadAndInstall(
        'http://127.0.0.1:1/app.apk',
      );

      expect(result, isFalse);
    });

    test('attempts download on 200 (method channel may reject)', () async {
      final result = await _withMockClient(
        () => UpdateService().downloadAndInstall('http://example.com/app.apk'),
        200,
        'fake apk bytes',
      );

      // The MethodChannel call will fail in test, so result is false.
      expect(result, isFalse);
    });
  });
}
