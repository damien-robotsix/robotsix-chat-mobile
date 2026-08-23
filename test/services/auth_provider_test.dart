import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  late MockClient mockClient;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockClient = MockClient();
  });

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------
  group('OidcTokenExchangeAuthProvider construction', () {
    test('stores baseUrl', () {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
      );
      expect(provider.baseUrl, 'https://chat.example.com');
    });

    test('stores subjectToken when provided', () {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'my-oidc-token',
      );
      expect(provider.subjectToken, 'my-oidc-token');
    });

    test('subjectToken is null when omitted', () {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
      );
      expect(provider.subjectToken, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // isLoggedIn
  // ---------------------------------------------------------------------------
  group('isLoggedIn', () {
    test('returns false when no subject token and no cached access token', () {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        client: mockClient,
      );
      expect(provider.isLoggedIn, isFalse);
    });

    test('returns true when subject token is present', () {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );
      expect(provider.isLoggedIn, isTrue);
    });

    test('returns false when subject token is empty string', () {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: '',
        client: mockClient,
      );
      expect(provider.isLoggedIn, isFalse);
    });

    test(
        'returns true after a successful exchange even when subjectToken '
        'is null (cached access token still valid)', () async {
      final now = DateTime(2026, 8, 21, 12);
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'at', 'expires_in': 3600}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
        clock: () => now,
      );

      await provider.requestHeaders();
      expect(provider.isLoggedIn, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // requestHeaders
  // ---------------------------------------------------------------------------
  group('requestHeaders', () {
    test('returns empty map when no subject token is set', () async {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        client: mockClient,
      );
      final headers = await provider.requestHeaders();
      expect(headers, isEmpty);
      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('exchanges subject token and returns Authorization header', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'fresh-token', 'expires_in': 3600}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subject-token',
        client: mockClient,
      );

      final headers = await provider.requestHeaders();
      expect(headers['Authorization'], 'Bearer fresh-token');
      expect(headers.length, 1);

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: jsonEncode({'token': 'subject-token'}),
        ),
      ).called(1);
    });

    test('reuses cached token on subsequent calls', () async {
      final now = DateTime(2026, 8, 21, 12);
      var clock = now;

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'tok-1', 'expires_in': 3600}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subject-token',
        client: mockClient,
        clock: () => clock,
      );

      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer tok-1',
      );

      // Advance clock by 5 minutes — still within expiry window.
      clock = now.add(const Duration(minutes: 5));
      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer tok-1',
      );

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('re-exchanges when cached token expires', () async {
      final now = DateTime(2026, 8, 21, 12);
      var clock = now;

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'tok-1', 'expires_in': 60}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subject-token',
        client: mockClient,
        clock: () => clock,
      );

      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer tok-1',
      );

      // Return a different token on the second exchange.
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'tok-2', 'expires_in': 60}),
          200,
        ),
      );

      // Advance past the 60-second expiry (minus the 1-minute skew, so
      // > 0 seconds — 60 seconds with 60-second skew = immediate expiry
      // after the minute mark).  We advance by 5 minutes to be safe.
      clock = now.add(const Duration(minutes: 5));
      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer tok-2',
      );

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(2);
    });

    test('throws ApiException on non-2xx exchange response', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('denied', 401));

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subject-token',
        client: mockClient,
      );

      expect(
        () => provider.requestHeaders(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // exchangeCodeForToken (public wrapper for _freshAccessToken)
  // ---------------------------------------------------------------------------
  group('exchangeCodeForToken', () {
    test('returns access token on successful exchange', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'at', 'expires_in': 3600}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );

      final token = await provider.exchangeCodeForToken();
      expect(token, 'at');
    });

    test('returns null when no subject token is available', () async {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        client: mockClient,
      );

      final token = await provider.exchangeCodeForToken();
      expect(token, isNull);

      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('throws FormatException when response is not JSON', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('not-json', 200));

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );

      expect(
        () => provider.exchangeCodeForToken(),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when response is missing access_token',
        () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'other_field': 'value'}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );

      expect(
        () => provider.exchangeCodeForToken(),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts "token" field as fallback for access_token', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'token': 'fallback-token', 'expires_in': 3600}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );

      final token = await provider.exchangeCodeForToken();
      expect(token, 'fallback-token');
    });

    test('prefers access_token over token when both present', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'primary',
            'token': 'fallback',
            'expires_in': 3600,
          }),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );

      final token = await provider.exchangeCodeForToken();
      expect(token, 'primary');
    });
  });

  // ---------------------------------------------------------------------------
  // clearCache
  // ---------------------------------------------------------------------------
  group('clearCache', () {
    test('forces re-exchange on next requestHeaders call', () async {
      final now = DateTime(2026, 8, 21, 12);
      var clock = now;

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'tok-1', 'expires_in': 3600}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
        clock: () => clock,
      );

      // First call — exchanges.
      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer tok-1',
      );

      // Clear cache and return a different token.
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'tok-2', 'expires_in': 3600}),
          200,
        ),
      );

      provider.clearCache();

      clock = now.add(const Duration(minutes: 1));
      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer tok-2',
      );

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(2);
    });
  });

  // ---------------------------------------------------------------------------
  // Token lifecycle edge cases
  // ---------------------------------------------------------------------------
  group('token lifecycle', () {
    test('no expires_in — token is never cached (exchanged every call)',
        () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'no-expiry-token'}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
      );

      await provider.requestHeaders();
      await provider.requestHeaders();

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(2);
    });

    test('clock skew margin — token refreshed before hard expiry', () async {
      final now = DateTime(2026, 8, 21, 12, 0, 0);
      var clock = now;

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'skew-tok', 'expires_in': 120}),
          200,
        ),
      );

      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: 'subj',
        client: mockClient,
        clock: () => clock,
      );

      // First exchange.
      await provider.requestHeaders();

      // Advance to 61 seconds — within the 120-second window but past
      // the 1-minute clock-skew margin (i.e. 120 - 60 = 60 seconds
      // effective lifetime).  At 61 seconds the cache is stale.
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'skew-tok-2', 'expires_in': 120}),
          200,
        ),
      );

      clock = now.add(const Duration(seconds: 61));
      await provider.requestHeaders();

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(2);
    });

    test('empty subject token returns null from exchange', () async {
      final provider = OidcTokenExchangeAuthProvider(
        baseUrl: 'https://chat.example.com',
        subjectToken: '',
        client: mockClient,
      );

      final token = await provider.exchangeCodeForToken();
      expect(token, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // authStateChanges
  // ---------------------------------------------------------------------------
  group('authStateChanges', () {
    test('emits true when subject token is saved', () async {
      await OidcTokenExchangeAuthProvider.saveSubjectToken('test-token');

      final emitted = await OidcTokenExchangeAuthProvider.authStateChanges.first;
      expect(emitted, isTrue);

      // Clean up
      await OidcTokenExchangeAuthProvider.clearSubjectToken();
      // Consume the false event from cleanup
      await OidcTokenExchangeAuthProvider.authStateChanges.first;
    });

    test('emits false when subject token is cleared', () async {
      await OidcTokenExchangeAuthProvider.saveSubjectToken('test-token');
      // Consume the true event
      await OidcTokenExchangeAuthProvider.authStateChanges.first;

      await OidcTokenExchangeAuthProvider.clearSubjectToken();
      final emitted = await OidcTokenExchangeAuthProvider.authStateChanges.first;
      expect(emitted, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // handleAuthCallback
  // ---------------------------------------------------------------------------
  group('handleAuthCallback', () {
    test('extracts token from URI and persists it', () async {
      final uri = Uri.parse('robotsixchat://auth/callback?token=my-sso-token');
      final result = await OidcTokenExchangeAuthProvider.handleAuthCallback(uri);

      expect(result, 'my-sso-token');
      final stored = await OidcTokenExchangeAuthProvider.getSubjectToken();
      expect(stored, 'my-sso-token');

      // Clean up
      await OidcTokenExchangeAuthProvider.clearSubjectToken();
      await OidcTokenExchangeAuthProvider.authStateChanges.first;
    });

    test('returns null when token parameter is missing', () async {
      final uri = Uri.parse('robotsixchat://auth/callback');
      final result = await OidcTokenExchangeAuthProvider.handleAuthCallback(uri);

      expect(result, isNull);
    });

    test('returns null when token parameter is empty', () async {
      final uri = Uri.parse('robotsixchat://auth/callback?token=');
      final result = await OidcTokenExchangeAuthProvider.handleAuthCallback(uri);

      expect(result, isNull);
    });
  });
}