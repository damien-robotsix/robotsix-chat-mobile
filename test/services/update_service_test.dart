import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:robotsix_chat_mobile/services/update_service.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late UpdateService service;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockClient = MockClient();
    service = UpdateService(client: mockClient);
  });

  // ---------------------------------------------------------------------------
  // _stripBuildNumber
  // ---------------------------------------------------------------------------
  group('_stripBuildNumber', () {
    test('strips build number suffix', () {
      final s = UpdateService();
      expect(s.stripBuildNumber('0.1.0+1'), '0.1.0');
    });

    test('returns unchanged when no build number', () {
      final s = UpdateService();
      expect(s.stripBuildNumber('0.1.0'), '0.1.0');
    });

    test('handles version with plus sign in middle', () {
      final s = UpdateService();
      expect(s.stripBuildNumber('0.1.0+a1b2c3'), '0.1.0');
    });
  });

  // ---------------------------------------------------------------------------
  // _isNewer
  // ---------------------------------------------------------------------------
  group('_isNewer', () {
    test('a > b returns true', () {
      final s = UpdateService();
      expect(s.isNewer('0.2.0', '0.1.0'), isTrue);
    });

    test('a < b returns false', () {
      final s = UpdateService();
      expect(s.isNewer('0.1.0', '0.2.0'), isFalse);
    });

    test('a == b returns false', () {
      final s = UpdateService();
      expect(s.isNewer('0.1.0', '0.1.0'), isFalse);
    });

    test('different lengths: longer wins if higher', () {
      final s = UpdateService();
      expect(s.isNewer('1.0.0.1', '1.0.0'), isTrue);
    });

    test('different lengths: shorter is padded with zeros', () {
      final s = UpdateService();
      expect(s.isNewer('1.0', '1.0.0'), isFalse);
    });

    test('non-numeric parts return false', () {
      final s = UpdateService();
      expect(s.isNewer('one.two', '1.0.0'), isFalse);
    });

    test('major version bump', () {
      final s = UpdateService();
      expect(s.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('minor version bump', () {
      final s = UpdateService();
      expect(s.isNewer('0.2.0', '0.1.9'), isTrue);
    });

    test('patch version bump', () {
      final s = UpdateService();
      expect(s.isNewer('0.1.2', '0.1.1'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // checkForUpdate
  // ---------------------------------------------------------------------------
  group('checkForUpdate', () {
    const currentVersion = '0.1.0';
    const latestVersion = '0.2.0';
    const apkUrl = 'https://github.com/damien-robotsix/robotsix-chat-mobile/releases/download/v0.2.0/app.apk';

    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'com.test',
        version: currentVersion,
        buildNumber: '1',
        buildSignature: 'test',
        installerStore: 'test',
      );
    });

    Map<String, dynamic> releaseJson({
      required String tag,
      required List<Map<String, dynamic>> assets,
    }) {
      return {
        'tag_name': tag,
        'assets': assets,
      };
    }

    Map<String, dynamic> apkAsset(String name, String url) {
      return {'name': name, 'browser_download_url': url};
    }

    test('returns available when newer release exists', () async {
      final body = releaseJson(
        tag: 'v$latestVersion',
        assets: [apkAsset('app-release.apk', apkUrl)],
      );

      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response(jsonEncode(body), 200));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.currentVersion, currentVersion);
      expect(result.latestVersion, latestVersion);
      expect(result.apkDownloadUrl, apkUrl);
    });

    test('returns upToDate when current == latest', () async {
      final body = releaseJson(
        tag: 'v$currentVersion',
        assets: [apkAsset('app-release.apk', apkUrl)],
      );

      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response(jsonEncode(body), 200));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.upToDate);
      expect(result.currentVersion, currentVersion);
    });

    test('returns upToDate when current > latest', () async {
      final body = releaseJson(
        tag: 'v0.0.9',
        assets: [apkAsset('app-release.apk', apkUrl)],
      );

      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response(jsonEncode(body), 200));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.upToDate);
    });

    test('returns error on non-200 response', () async {
      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response('Not Found', 404));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('404'));
    });

    test('returns error on 500 response', () async {
      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response('Server Error', 500));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('500'));
    });

    test('returns error on SocketException', () async {
      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenThrow(const SocketException('No connection'));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('Network unavailable'));
    });

    test('returns error on ClientException', () async {
      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenThrow(http.ClientException('Connection failed'));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('Network error'));
    });

    test('returns error when no APK asset in release', () async {
      final body = releaseJson(
        tag: 'v$latestVersion',
        assets: [
          {'name': 'source.zip', 'browser_download_url': 'https://example.com/src.zip'},
        ],
      );

      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response(jsonEncode(body), 200));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('No APK asset'));
    });

    test('returns error on malformed JSON', () async {
      when(
        () => mockClient.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => http.Response('not json', 200));

      final result = await service.checkForUpdate();

      expect(result.status, UpdateStatus.error);
      expect(result.errorMessage, contains('Invalid API response'));
    });
  });

  // ---------------------------------------------------------------------------
  // downloadAndInstall
  // ---------------------------------------------------------------------------
  group('downloadAndInstall', () {
    const apkData = [0xDE, 0xAD, 0xBE, 0xEF];
    late String cacheDir;

    setUp(() async {
      final tempDir =
          await Directory.systemTemp.createTemp('update_service_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationCacheDirectory') {
            return tempDir.path;
          }
          return null;
        },
      );
      cacheDir = (await getApplicationCacheDirectory()).path;
    });

    tearDown(() {
      // Clear any install-channel handler set by an individual test so it
      // doesn't leak into the next one.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.robotsix.chat_mobile/install'),
        null,
      );
    });

    test('completes without throwing on success', () async {
      var installInvoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.robotsix.chat_mobile/install'),
        (call) async {
          expect(call.method, 'installApk');
          expect(call.arguments['path'], contains('update.apk'));
          installInvoked = true;
          return true;
        },
      );

      when(
        () => mockClient.get(any()),
      ).thenAnswer(
        (_) async => http.Response.bytes(apkData, 200),
      );

      await service.downloadAndInstall('https://example.com/update.apk');

      expect(installInvoked, isTrue);

      // Verify the file was written.
      final apkFile = File('$cacheDir/update.apk');
      expect(apkFile.existsSync(), isTrue);
      expect(apkFile.readAsBytesSync(), apkData);
    });

    test('throws downloadFailed on non-200 response', () async {
      when(
        () => mockClient.get(any()),
      ).thenAnswer(
        (_) async => http.Response('Forbidden', 403),
      );

      await expectLater(
        service.downloadAndInstall('https://example.com/update.apk'),
        throwsA(
          isA<InstallException>().having(
            (e) => e.kind,
            'kind',
            InstallErrorKind.downloadFailed,
          ),
        ),
      );
    });

    test('throws downloadFailed on SocketException', () async {
      when(
        () => mockClient.get(any()),
      ).thenThrow(const SocketException('No connection'));

      await expectLater(
        service.downloadAndInstall('https://example.com/update.apk'),
        throwsA(
          isA<InstallException>().having(
            (e) => e.kind,
            'kind',
            InstallErrorKind.downloadFailed,
          ),
        ),
      );
    });

    test('throws permissionRequired when native reports PERMISSION_REQUIRED',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.robotsix.chat_mobile/install'),
        (call) async {
          throw PlatformException(
            code: 'PERMISSION_REQUIRED',
            message: 'Permission to install unknown apps is required.',
          );
        },
      );

      when(
        () => mockClient.get(any()),
      ).thenAnswer(
        (_) async => http.Response.bytes(apkData, 200),
      );

      await expectLater(
        service.downloadAndInstall('https://example.com/update.apk'),
        throwsA(
          isA<InstallException>().having(
            (e) => e.kind,
            'kind',
            InstallErrorKind.permissionRequired,
          ),
        ),
      );
    });

    test('throws platformError on other PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.robotsix.chat_mobile/install'),
        (call) async {
          throw PlatformException(
            code: 'INSTALL_ERROR',
            message: 'Failed to launch install',
          );
        },
      );

      when(
        () => mockClient.get(any()),
      ).thenAnswer(
        (_) async => http.Response.bytes(apkData, 200),
      );

      await expectLater(
        service.downloadAndInstall('https://example.com/update.apk'),
        throwsA(
          isA<InstallException>().having(
            (e) => e.kind,
            'kind',
            InstallErrorKind.platformError,
          ),
        ),
      );
    });

    test('throws pluginMissing when native handler is absent', () async {
      // No handler registered for the install channel → invokeMethod
      // raises a MissingPluginException (simulates an old installed build
      // that predates the native installApk handler).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.robotsix.chat_mobile/install'),
        null,
      );

      when(
        () => mockClient.get(any()),
      ).thenAnswer(
        (_) async => http.Response.bytes(apkData, 200),
      );

      await expectLater(
        service.downloadAndInstall('https://example.com/update.apk'),
        throwsA(
          isA<InstallException>().having(
            (e) => e.kind,
            'kind',
            InstallErrorKind.pluginMissing,
          ),
        ),
      );
    });
  });
}
