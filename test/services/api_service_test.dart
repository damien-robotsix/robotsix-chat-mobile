import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  group('ApiService', () {
    test('can be constructed with baseUrl and authProvider', () {
      final svc = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: OidcTokenExchangeAuthProvider(
          baseUrl: 'https://chat.example.com',
        ),
      );
      expect(svc.baseUrl, 'https://chat.example.com');
    });

    test('can be constructed with a token', () {
      final svc = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: OidcTokenExchangeAuthProvider(
          baseUrl: 'https://chat.example.com',
          subjectToken: 'tok-123',
        ),
      );
      expect(svc.baseUrl, 'https://chat.example.com');
    });
  });

  group('ApiException', () {
    test('stores statusCode and body', () {
      const ex = ApiException(404, 'Not Found');
      expect(ex.statusCode, 404);
      expect(ex.body, 'Not Found');
    });

    test('toString includes status and body', () {
      const ex = ApiException(500, 'Internal Server Error');
      expect(ex.toString(), contains('500'));
      expect(ex.toString(), contains('Internal Server Error'));
    });
  });

  group('ChatEvent', () {
    test('TokenEvent stores content', () {
      const ev = TokenEvent('hello');
      expect(ev.content, 'hello');
    });

    test('DoneEvent stores sessionId and timestamp', () {
      const ev = DoneEvent(sessionId: 's1', timestamp: 1.5);
      expect(ev.sessionId, 's1');
      expect(ev.timestamp, 1.5);
    });

    test('ErrorEvent stores message, code, and optional correlationId', () {
      const ev = ErrorEvent(
        message: 'bad request',
        code: 'BAD_REQ',
        correlationId: 'abc-123',
      );
      expect(ev.message, 'bad request');
      expect(ev.code, 'BAD_REQ');
      expect(ev.correlationId, 'abc-123');
    });

    test('ErrorEvent correlationId can be null', () {
      const ev = ErrorEvent(message: 'oops', code: 'ERR');
      expect(ev.correlationId, isNull);
    });
  });

  group('ChatSession', () {
    test('fromJson parses session_id, title, turn_count', () {
      final session = ChatSession.fromJson({
        'session_id': 's1',
        'title': 'My chat',
        'turn_count': 3,
      });
      expect(session.sessionId, 's1');
      expect(session.title, 'My chat');
      expect(session.turnCount, 3);
    });

    test('fromJson handles missing optional fields', () {
      final session = ChatSession.fromJson({'session_id': 's2'});
      expect(session.sessionId, 's2');
      expect(session.title, isNull);
      expect(session.turnCount, isNull);
    });
  });

  group('OidcTokenExchangeAuthProvider', () {
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      registerFallbackValue(Uri());
    });

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

    test('exchanges the subject token for an access token', () async {
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

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: jsonEncode({'token': 'subject-token'}),
        ),
      ).called(1);
    });

    test('reuses a cached token until it expires', () async {
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
          jsonEncode({'access_token': 'fresh-token', 'expires_in': 3600}),
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
        'Bearer fresh-token',
      );

      clock = now.add(const Duration(minutes: 5));
      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer fresh-token',
      );

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('refreshes an expired token', () async {
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
          jsonEncode({'access_token': 'token-1', 'expires_in': 60}),
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
        'Bearer token-1',
      );

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'access_token': 'token-2', 'expires_in': 60}),
          200,
        ),
      );

      clock = now.add(const Duration(minutes: 5));
      expect(
        (await provider.requestHeaders())['Authorization'],
        'Bearer token-2',
      );

      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(2);
    });

    test('throws ApiException when the exchange fails', () async {
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
}
