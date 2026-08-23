import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

class MockClient extends Mock implements http.Client {}

class MockAuthProvider extends Mock implements AuthProvider {}

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

  group('ApiService session methods', () {
    late ApiService apiService;

    setUp(() {
      SharedPreferences.setMockInitialValues({'owner_id': 'test-owner'});
    });

    ApiService _createService(MockAuthProvider auth) {
      return ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: auth,
      );
    }

    // ------------------------------------------------------------------
    // listSessions
    // ------------------------------------------------------------------

    test('listSessions returns parsed session list on 200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), contains('/sessions'));
        expect(request.headers['Authorization'], 'Bearer tok');
        return http.Response(
          '[{"session_id":"s1","title":"Chat 1","turn_count":2},'
          '{"session_id":"s2"}]',
          200,
        );
      });

      final svc = _createService(mockAuth);

      final sessions = await http.runWithClient(
        () => svc.listSessions(),
        () => mockClient,
      );

      expect(sessions, hasLength(2));
      expect(sessions[0].sessionId, 's1');
      expect(sessions[0].title, 'Chat 1');
      expect(sessions[0].turnCount, 2);
      expect(sessions[1].sessionId, 's2');
      expect(sessions[1].title, isNull);
      expect(sessions[1].turnCount, isNull);
    });

    test('listSessions throws ApiException on non-200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        return http.Response('{"error":"unauthorized"}', 401);
      });

      final svc = _createService(mockAuth);

      expect(
        () => http.runWithClient(
          () => svc.listSessions(),
          () => mockClient,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    // ------------------------------------------------------------------
    // createSession
    // ------------------------------------------------------------------

    test('createSession returns ChatSession on 200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), contains('/sessions'));
        expect(request.body, contains('test-owner'));
        return http.Response(
          '{"session_id":"new-session","title":null,"turn_count":0}',
          200,
        );
      });

      final svc = _createService(mockAuth);

      final session = await http.runWithClient(
        () => svc.createSession(),
        () => mockClient,
      );

      expect(session.sessionId, 'new-session');
    });

    test('createSession throws ApiException on non-200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        return http.Response('server error', 500);
      });

      final svc = _createService(mockAuth);

      expect(
        () => http.runWithClient(
          () => svc.createSession(),
          () => mockClient,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    // ------------------------------------------------------------------
    // deleteSession
    // ------------------------------------------------------------------

    test('deleteSession succeeds on 200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), contains('/sessions/sess-1'));
        return http.Response('', 200);
      });

      final svc = _createService(mockAuth);

      await http.runWithClient(
        () => svc.deleteSession('sess-1'),
        () => mockClient,
      );
    });

    test('deleteSession throws ApiException on non-200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        return http.Response('not found', 404);
      });

      final svc = _createService(mockAuth);

      expect(
        () => http.runWithClient(
          () => svc.deleteSession('sess-1'),
          () => mockClient,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    // ------------------------------------------------------------------
    // closeSession
    // ------------------------------------------------------------------

    test('closeSession succeeds on 200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), contains('/sessions/sess-1/close'));
        return http.Response('', 200);
      });

      final svc = _createService(mockAuth);

      await http.runWithClient(
        () => svc.closeSession('sess-1'),
        () => mockClient,
      );
    });

    test('closeSession throws ApiException on non-200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        return http.Response('conflict', 409);
      });

      final svc = _createService(mockAuth);

      expect(
        () => http.runWithClient(
          () => svc.closeSession('sess-1'),
          () => mockClient,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    // ------------------------------------------------------------------
    // getHistory
    // ------------------------------------------------------------------

    test('getHistory returns parsed history on 200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), contains('/history'));
        expect(request.url.toString(), contains('session_id=sess-1'));
        return http.Response(
          '[{"role":"user","content":"hi"},{"role":"agent","content":"hello"}]',
          200,
        );
      });

      final svc = _createService(mockAuth);

      final history = await http.runWithClient(
        () => svc.getHistory('sess-1'),
        () => mockClient,
      );

      expect(history, hasLength(2));
      expect(history[0]['role'], 'user');
      expect(history[1]['role'], 'agent');
    });

    test('getHistory throws ApiException on non-200', () async {
      final mockAuth = MockAuthProvider();
      when(mockAuth.requestHeaders).thenAnswer(
        (_) async => {'Authorization': 'Bearer tok'},
      );

      final mockClient = http_testing.MockClient((request) async {
        return http.Response('not found', 404);
      });

      final svc = _createService(mockAuth);

      expect(
        () => http.runWithClient(
          () => svc.getHistory('sess-1'),
          () => mockClient,
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
