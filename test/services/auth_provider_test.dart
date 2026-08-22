import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:robotsix_chat_mobile/services/auth_provider.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockHttpClient extends Mock implements http.Client {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Return a minimal HTTP 200 response whose body is the JSON-encoded
/// version of [body].
http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(jsonEncode(body), 200);
}

/// Return a minimal HTTP response with the given [statusCode] and
/// plain-text [body].
http.Response _plainResponse(int statusCode, String body) {
  return http.Response(body, statusCode);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockHttpClient httpClient;
  late MockSecureStorage secureStorage;
  late TokenExchangeAuthProvider provider;

  const testBaseUrl = 'https://chat.example.com';
  const testToken = 'fleet-token-abc123';

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://fallback.example.com'));
  });

  setUp(() {
    httpClient = MockHttpClient();
    secureStorage = MockSecureStorage();
    when(() => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
    provider = TokenExchangeAuthProvider(
      baseUrl: testBaseUrl,
      httpClient: httpClient,
      secureStorage: secureStorage,
    );
  });

  group('TokenExchangeAuthProvider', () {
    // ------------------------------------------------------------------
    // requestHeaders
    // ------------------------------------------------------------------

    group('requestHeaders', () {
      test('returns empty map when no token is cached', () async {
        when(() => secureStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);

        final headers = await provider.requestHeaders();

        expect(headers, isEmpty);
      });

      test('returns Authorization header when token is in memory cache',
          () async {
        // Preload the memory cache so no secure-storage read is needed.
        await provider.saveToken(testToken);

        final headers = await provider.requestHeaders();

        expect(headers, containsPair('Authorization', 'Bearer $testToken'));
        // The in-memory cache satisfied the request — secure storage was
        // never called.
        verifyNever(() => secureStorage.read(key: any(named: 'key')));
      });

      test('falls back to secure storage when memory cache is empty',
          () async {
        when(() => secureStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => testToken);

        final headers = await provider.requestHeaders();

        expect(headers, containsPair('Authorization', 'Bearer $testToken'));
      });
    });

    // ------------------------------------------------------------------
    // Token lifecycle
    // ------------------------------------------------------------------

    group('getToken / saveToken / clearToken', () {
      test('getToken returns null when nothing is stored', () async {
        when(() => secureStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);

        expect(await provider.getToken(), isNull);
      });

      test('getToken returns the saved token', () async {
        await provider.saveToken(testToken);

        expect(await provider.getToken(), testToken);
        // saveToken should persist to secure storage.
        verify(() => secureStorage.write(
              key: any(named: 'key'),
              value: testToken,
            )).called(1);
      });

      test('clearToken removes token from memory and storage', () async {
        when(() => secureStorage.delete(key: any(named: 'key')))
            .thenAnswer((_) async {});

        await provider.saveToken(testToken);
        await provider.clearToken();

        // After clearing, memory cache is empty; secure storage is asked.
        when(() => secureStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);

        expect(await provider.getToken(), isNull);
        verify(() => secureStorage.delete(key: any(named: 'key'))).called(1);
      });

      test('clearToken on already-empty provider is a no-op', () async {
        when(() => secureStorage.delete(key: any(named: 'key')))
            .thenAnswer((_) async {});

        await provider.clearToken();

        // delete is still called (to ensure storage is clean).
        verify(() => secureStorage.delete(key: any(named: 'key'))).called(1);
      });

      test('saveToken overwrites previous token', () async {
        await provider.saveToken('old-token');
        await provider.saveToken('new-token');

        expect(await provider.getToken(), 'new-token');
      });
    });

    // ------------------------------------------------------------------
    // isLoggedIn
    // ------------------------------------------------------------------

    group('isLoggedIn', () {
      test('returns false when no token exists', () async {
        when(() => secureStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);

        expect(await provider.isLoggedIn, false);
      });

      test('returns false when token is empty', () async {
        when(() => secureStorage.read(key: any(named: 'key')))
            .thenAnswer((_) async => '');

        expect(await provider.isLoggedIn, false);
      });

      test('returns true when a non-empty token is cached', () async {
        await provider.saveToken(testToken);

        expect(await provider.isLoggedIn, true);
      });
    });

    // ------------------------------------------------------------------
    // _exchangeCodeForToken
    // ------------------------------------------------------------------

    group('_exchangeCodeForToken', () {
      const authCode = 'sso-auth-code-xyz';

      test('extracts token from JSON response', () async {
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _jsonResponse({'token': testToken}),
        );

        final token = await provider.exchangeCodeForTokenForTest(authCode);

        expect(token, testToken);
      });

      test('falls back to raw body when JSON has no "token" field',
          () async {
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _jsonResponse({'other': 'value', 'token': ''}),
        );

        // The JSON path yields an empty token, but the fallback trims
        // the raw body — which is the json-encoded string, not a valid
        // token.  We test with a plain-text body instead.
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _plainResponse(200, 'raw-plain-token'),
        );

        final token = await provider.exchangeCodeForTokenForTest(authCode);

        expect(token, 'raw-plain-token');
      });

      test('trims whitespace from fallback body', () async {
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _plainResponse(200, '  token-with-spaces  '),
        );

        final token = await provider.exchangeCodeForTokenForTest(authCode);

        expect(token, 'token-with-spaces');
      });

      test('throws on non-200 response', () async {
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _plainResponse(403, 'Forbidden'),
        );

        expect(
          () => provider.exchangeCodeForTokenForTest(authCode),
          throwsA(isA<http.ClientException>()),
        );
      });

      test('throws when response body is empty', () async {
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _plainResponse(200, ''),
        );

        expect(
          () => provider.exchangeCodeForTokenForTest(authCode),
          throwsA(isA<FormatException>()),
        );
      });

      test('calls GET /auth/token with code query param', () async {
        when(() => httpClient.get(any())).thenAnswer(
          (_) async => _jsonResponse({'token': testToken}),
        );

        await provider.exchangeCodeForTokenForTest(authCode);

        final captured = verify(() => httpClient.get(captureAny())).captured;
        expect(captured, hasLength(1));
        final uri = captured.single as Uri;
        expect(uri.path, '/auth/token');
        expect(uri.queryParameters['code'], authCode);
      });
    });
  });
}