import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/models/api_exception.dart';
import 'package:robotsix_chat_mobile/models/chat_event.dart';
import 'package:robotsix_chat_mobile/models/chat_session.dart';
import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

class MockClient extends Mock implements http.Client {}

class MockAuthProvider extends Mock implements AuthProvider {}

/// Render a single SSE `data:` frame terminated by a blank line.
String _frame(Map<String, dynamic> data) => 'data: ${jsonEncode(data)}\n\n';

/// Build a [http.StreamedResponse] that emits [body] as a single UTF-8
/// chunk with the given [statusCode].
http.StreamedResponse _sseResponse(String body, {int statusCode = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode);

/// Build a [http.StreamedResponse] that emits each entry of [chunks] as a
/// separate UTF-8 byte chunk, to exercise buffer-boundary handling.
http.StreamedResponse _sseChunks(List<String> chunks, {int statusCode = 200}) =>
    http.StreamedResponse(
      Stream.fromIterable(chunks.map(utf8.encode)),
      statusCode,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('ApiService.sendMessage', () {
    late MockClient mockClient;
    late MockAuthProvider mockAuth;

    setUp(() {
      mockClient = MockClient();
      mockAuth = MockAuthProvider();
      registerFallbackValue(http.Request('POST', Uri()));
      when(() => mockAuth.requestHeaders())
          .thenAnswer((_) async => <String, String>{});
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues({});
    });

    ApiService buildService() => ApiService(
      baseUrl: 'https://chat.example.com',
      authProvider: mockAuth,
      client: mockClient,
    );

    test('streams token events then a done event', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => _sseResponse(
          _frame({'type': 'token', 'content': 'Hello'}) +
              _frame({'type': 'token', 'content': ' world'}) +
              _frame({'type': 'done', 'session_id': 's-1', 'timestamp': 1.5}),
        ),
      );

      final events = await buildService().sendMessage(message: 'hi').toList();

      expect(events, hasLength(3));
      expect((events[0] as TokenEvent).content, 'Hello');
      expect((events[1] as TokenEvent).content, ' world');
      final done = events[2] as DoneEvent;
      expect(done.sessionId, 's-1');
      expect(done.timestamp, 1.5);
    });

    test('posts to /chat with message, ids and SSE headers', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => _sseResponse(
          _frame({'type': 'done', 'session_id': 's', 'timestamp': 0}),
        ),
      );

      await buildService()
          .sendMessage(message: 'hello', sessionId: 'sess-1', messageId: 'm-1')
          .toList();

      final captured = verify(() => mockClient.send(captureAny())).captured;
      final request = captured.single as http.Request;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://chat.example.com/chat');
      expect(request.headers['Accept'], 'text/event-stream');
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      expect(decoded['message'], 'hello');
      expect(decoded['session_id'], 'sess-1');
      expect(decoded['message_id'], 'm-1');
      expect(decoded['owner_id'], isNotEmpty);
    });

    test('omits session_id and message_id when not provided', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => _sseResponse(
          _frame({'type': 'done', 'session_id': 's', 'timestamp': 0}),
        ),
      );

      await buildService().sendMessage(message: 'first').toList();

      final captured = verify(() => mockClient.send(captureAny())).captured;
      final decoded = jsonDecode(
        (captured.single as http.Request).body,
      ) as Map<String, dynamic>;
      expect(decoded.containsKey('session_id'), isFalse);
      expect(decoded.containsKey('message_id'), isFalse);
    });

    test('throws AuthException on a 401 response', () async {
      when(
        () => mockClient.send(any()),
      ).thenAnswer((_) async => _sseResponse('unauthorized', statusCode: 401));

      expect(
        () => buildService().sendMessage(message: 'hi').toList(),
        throwsA(
          isA<AuthException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws AuthException on a 403 response', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => _sseResponse('forbidden', statusCode: 403));

      expect(
        () => buildService().sendMessage(message: 'hi').toList(),
        throwsA(
          isA<AuthException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 500 response', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => _sseResponse('boom', statusCode: 500));

      expect(
        () => buildService().sendMessage(message: 'hi').toList(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.body, 'body', 'boom'),
        ),
      );
    });

    test('propagates a network error raised while sending', () async {
      when(() => mockClient.send(any()))
          .thenThrow(http.ClientException('connection refused'));

      expect(
        () => buildService().sendMessage(message: 'hi').toList(),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('propagates a network error raised mid-stream', () async {
      Stream<List<int>> failing() async* {
        yield utf8.encode(_frame({'type': 'token', 'content': 'x'}));
        throw http.ClientException('dropped');
      }

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => http.StreamedResponse(failing(), 200));

      expect(
        () => buildService().sendMessage(message: 'hi').toList(),
        throwsA(isA<http.ClientException>()),
      );
    });

    // -- _parseSseStream behaviour, exercised via sendMessage --------------

    test(
      'parses an error event with message, code and correlationId',
      () async {
        when(() => mockClient.send(any())).thenAnswer(
          (_) async => _sseResponse(
            _frame({
              'type': 'error',
              'message': 'bad request',
              'code': 'BAD_REQ',
              'correlation_id': 'corr-9',
            }),
          ),
        );

        final events = await buildService().sendMessage(message: 'hi').toList();

        final err = events.single as ErrorEvent;
        expect(err.message, 'bad request');
        expect(err.code, 'BAD_REQ');
        expect(err.correlationId, 'corr-9');
      },
    );

    test('applies defaults for missing token/done/error fields', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => _sseResponse(
          _frame({'type': 'token'}) +
              _frame({'type': 'done'}) +
              _frame({'type': 'error'}),
        ),
      );

      final events = await buildService().sendMessage(message: 'hi').toList();

      expect((events[0] as TokenEvent).content, '');
      final done = events[1] as DoneEvent;
      expect(done.sessionId, '');
      expect(done.timestamp, 0.0);
      final err = events[2] as ErrorEvent;
      expect(err.message, 'Unknown error');
      expect(err.code, 'unknown');
      expect(err.correlationId, isNull);
    });

    test(
      'skips comments, blank lines, malformed JSON and unknown event types',
      () async {
        when(() => mockClient.send(any())).thenAnswer(
          (_) async => _sseResponse(
            ': keepalive\n'
            '\n'
            'data: \n\n'
            'data: not-json\n\n'
            '${_frame({'type': 'mystery', 'content': 'ignored'})}'
            '${_frame({'type': 'token', 'content': 'survived'})}',
          ),
        );

        final events = await buildService().sendMessage(message: 'hi').toList();

        expect(events, hasLength(1));
        expect((events.single as TokenEvent).content, 'survived');
      },
    );

    test('reassembles a frame split across chunk boundaries', () async {
      final full = _frame({'type': 'token', 'content': 'chunked'});
      final mid = full.length ~/ 2;

      when(() => mockClient.send(any())).thenAnswer(
        (_) async => _sseChunks([full.substring(0, mid), full.substring(mid)]),
      );

      final events = await buildService().sendMessage(message: 'hi').toList();

      expect(events, hasLength(1));
      expect((events.single as TokenEvent).content, 'chunked');
    });

    test('does not emit for an incomplete, unterminated frame', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async =>
            _sseResponse('data: {"type": "token", "content": "partial"'),
      );

      final events = await buildService().sendMessage(message: 'hi').toList();

      expect(events, isEmpty);
    });
  });

  group('ApiService.getOwnerId', () {
    // A JWT whose payload is {"sub":"sso-user-42"} (signature ignored).
    const jwtForSsoUser42 =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiJzc28tdXNlci00MiJ9.'
        'c2lnbmF0dXJl';

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('derives owner_id from the authenticated SSO subject', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await OidcTokenExchangeAuthProvider.saveSubjectToken(jwtForSsoUser42);

      final ownerId = await ApiService.getOwnerId();

      expect(ownerId, 'sso-user-42');
    });

    test(
      'replaces a previously-generated random id with the subject',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'owner_id': 'random-device-id',
        });
        await OidcTokenExchangeAuthProvider.saveSubjectToken(jwtForSsoUser42);

        final ownerId = await ApiService.getOwnerId();

        expect(ownerId, 'sso-user-42');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('owner_id'), 'sso-user-42');
      },
    );

    test('falls back to a stable per-install id when not logged in', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final first = await ApiService.getOwnerId();
      final second = await ApiService.getOwnerId();

      expect(first, isNotEmpty);
      expect(second, first);
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

      expect(() => provider.requestHeaders(), throwsA(isA<ApiException>()));
    });
  });

  // ---------------------------------------------------------------------------
  // AuthException
  // ---------------------------------------------------------------------------
  group('AuthException', () {
    test('stores statusCode and body', () {
      const ex = AuthException(401, 'Unauthorized');
      expect(ex.statusCode, 401);
      expect(ex.body, 'Unauthorized');
    });

    test('is an ApiException', () {
      const ex = AuthException(403, 'Forbidden');
      expect(ex, isA<ApiException>());
    });

    test('message is a user-friendly re-login prompt', () {
      const ex = AuthException(401, 'Token expired');
      expect(ex.message, contains('Session expired'));
      expect(ex.message, contains('Settings'));
    });

    test('toString includes statusCode and body', () {
      const ex = AuthException(401, 'Unauthorized');
      expect(ex.toString(), contains('401'));
      expect(ex.toString(), contains('Unauthorized'));
    });
  });

  group('ApiException.message', () {
    test('returns body by default', () {
      const ex = ApiException(500, 'Server Error');
      expect(ex.message, 'Server Error');
    });
  });

  group('ApiService methods', () {
    late MockClient mockClient;
    late MockAuthProvider mockAuthProvider;
    late ApiService apiService;

    setUp(() {
      // deleteSession/closeSession resolve an owner id via
      // ApiService.getOwnerId(), which reads SharedPreferences. Without a
      // mock store that throws MissingPluginException under `flutter test`.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues({});
      mockClient = MockClient();
      mockAuthProvider = MockAuthProvider();
      registerFallbackValue(Uri());
      when(() => mockAuthProvider.requestHeaders())
          .thenAnswer((_) async => {'Authorization': 'Bearer test-token'});
      apiService = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: mockAuthProvider,
        client: mockClient,
      );
    });

    // -- listSessions --------------------------------------------------

    group('listSessions', () {
      test('returns parsed session list on 200', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async {
              return http.Response(
                jsonEncode({
                  'sessions': [
                    {'session_id': 's1', 'title': 'First', 'turn_count': 5},
                    {'session_id': 's2', 'title': 'Second', 'turn_count': 0},
                  ],
                  'active_session_id': 's1',
                }),
                200,
              );
            });

        final sessions = await apiService.listSessions();

        expect(sessions, hasLength(2));
        expect(sessions[0].sessionId, 's1');
        expect(sessions[0].title, 'First');
        expect(sessions[0].turnCount, 5);
        expect(sessions[1].sessionId, 's2');
      });

      test('returns empty list when sessions key is missing', () async {
        when(
          () => mockClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async {
          return http.Response(jsonEncode({'active_session_id': null}), 200);
        });

        final sessions = await apiService.listSessions();

        expect(sessions, isEmpty);
      });

      test('throws AuthException on 401', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('unauthorized', 401));

        await expectLater(
          apiService.listSessions(),
          throwsA(isA<AuthException>()),
        );
      });

      test(
        'does not wipe a saved subject token on a stale-client 401',
        () async {
          // A stale client built (token-less) before login must not wipe a
          // credential saved by a newer auth flow when it receives a 401.
          await OidcTokenExchangeAuthProvider.saveSubjectToken('tok-123');
          final staleService = ApiService(
            baseUrl: 'https://chat.example.com',
            authProvider: OidcTokenExchangeAuthProvider(
              baseUrl: 'https://chat.example.com',
            ),
            client: mockClient,
          );
          when(() => mockClient.get(any(), headers: any(named: 'headers')))
              .thenAnswer((_) async => http.Response('unauthorized', 401));

          await expectLater(
            staleService.listSessions(),
            throwsA(isA<AuthException>()),
          );
          expect(
            await OidcTokenExchangeAuthProvider.getSubjectToken(),
            'tok-123',
          );
        },
      );

      test('clears the subject token on a genuine 401 when the client has '
          'one', () async {
        final exchangeClient = MockClient();
        when(
          () => exchangeClient.post(
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
        await OidcTokenExchangeAuthProvider.saveSubjectToken('tok-123');
        final authedService = ApiService(
          baseUrl: 'https://chat.example.com',
          authProvider: OidcTokenExchangeAuthProvider(
            baseUrl: 'https://chat.example.com',
            subjectToken: 'tok-123',
            client: exchangeClient,
          ),
          client: mockClient,
        );
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('unauthorized', 401));

        await expectLater(
          authedService.listSessions(),
          throwsA(isA<AuthException>()),
        );
        expect(await OidcTokenExchangeAuthProvider.getSubjectToken(), isNull);
      });

      test('throws ApiException on non-200', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('server error', 500));

        await expectLater(
          apiService.listSessions(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    // -- createSession -------------------------------------------------

    group('createSession', () {
      test('returns created session on 200', () async {
        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async {
          return http.Response(
            jsonEncode({
              'session_id': 'new-session',
              'title': null,
              'turn_count': 0,
            }),
            200,
          );
        });

        final session = await apiService.createSession();

        expect(session.sessionId, 'new-session');
        expect(session.turnCount, 0);
      });

      test('throws AuthException on 403', () async {
        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('forbidden', 403));

        await expectLater(
          apiService.createSession(),
          throwsA(isA<AuthException>()),
        );
      });

      test('throws ApiException on non-200', () async {
        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('bad request', 400));

        await expectLater(
          apiService.createSession(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    // -- deleteSession -------------------------------------------------

    group('deleteSession', () {
      test('completes on 200', () async {
        when(() => mockClient.delete(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('', 200));

        await apiService.deleteSession('s1');
        // No exception means success.
      });

      test('throws ApiException on non-200', () async {
        when(() => mockClient.delete(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('gone', 410));

        await expectLater(
          apiService.deleteSession('s1'),
          throwsA(isA<ApiException>()),
        );
      });

      test('throws AuthException on 401', () async {
        when(() => mockClient.delete(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('unauthorized', 401));

        await expectLater(
          apiService.deleteSession('s1'),
          throwsA(isA<AuthException>()),
        );
      });
    });

    // -- closeSession --------------------------------------------------

    group('closeSession', () {
      test('completes on 200', () async {
        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', 200));

        await apiService.closeSession('s1');
      });

      test('throws ApiException on non-200', () async {
        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('conflict', 409));

        await expectLater(
          apiService.closeSession('s1'),
          throwsA(isA<ApiException>()),
        );
      });

      test('throws AuthException on 403', () async {
        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('forbidden', 403));

        await expectLater(
          apiService.closeSession('s1'),
          throwsA(isA<AuthException>()),
        );
      });
    });

    // -- getHistory ----------------------------------------------------

    group('getHistory', () {
      test('parses the turns field of the {"turns": [...]} response', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async {
              return http.Response(
                jsonEncode({
                  'turns': [
                    {'role': 'user', 'content': 'hello'},
                    {'role': 'assistant', 'content': 'hi there'},
                  ],
                }),
                200,
              );
            });

        final history = await apiService.getHistory('s1');

        expect(history, hasLength(2));
        expect(history[0]['role'], 'user');
        expect(history[1]['content'], 'hi there');
      });

      test('returns an empty list when turns is absent', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response(jsonEncode({}), 200));

        final history = await apiService.getHistory('s1');

        expect(history, isEmpty);
      });

      test('throws ApiException on non-200', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('not found', 404));

        expect(apiService.getHistory('s1'), throwsA(isA<ApiException>()));
      });

      test('throws AuthException on 401', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('unauthorized', 401));

        expect(apiService.getHistory('s1'), throwsA(isA<AuthException>()));
      });
    });
  });
}
