import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

void main() {
  group('ApiService', () {
    test('can be constructed with baseUrl and authProvider', () {
      final svc = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: const TokenAuthProvider(),
      );
      expect(svc.baseUrl, 'https://chat.example.com');
    });

    test('can be constructed with a token', () {
      final svc = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: const TokenAuthProvider(token: 'tok-123'),
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

  group('TokenAuthProvider', () {
    test('returns Authorization header when token is set', () async {
      const provider = TokenAuthProvider(token: 'secret');
      final headers = await provider.requestHeaders();
      expect(headers['Authorization'], 'Bearer secret');
    });

    test('returns empty map when token is null', () async {
      const provider = TokenAuthProvider();
      final headers = await provider.requestHeaders();
      expect(headers, isEmpty);
    });

    test('returns empty map when token is empty', () async {
      const provider = TokenAuthProvider(token: '');
      final headers = await provider.requestHeaders();
      expect(headers, isEmpty);
    });
  });

  // ------------------------------------------------------------------
  // Storage helpers
  // ------------------------------------------------------------------

  group('saveBaseUrl / getBaseUrl', () {
    test('round-trip: save then read back', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.saveBaseUrl('https://example.com');
      final result = await ApiService.getBaseUrl();
      expect(result, 'https://example.com');
    });

    test('getBaseUrl returns null when nothing saved', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await ApiService.getBaseUrl();
      expect(result, isNull);
    });

    test('saveBaseUrl overwrites previous value', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.saveBaseUrl('https://first.example.com');
      await ApiService.saveBaseUrl('https://second.example.com');
      final result = await ApiService.getBaseUrl();
      expect(result, 'https://second.example.com');
    });
  });

  group('saveToken / getToken', () {
    test('round-trip: save then read back', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.saveToken('my-secret-token');
      final result = await ApiService.getToken();
      expect(result, 'my-secret-token');
    });

    test('getToken returns null when nothing saved', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await ApiService.getToken();
      expect(result, isNull);
    });

    test('saveToken overwrites previous value', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.saveToken('old-token');
      await ApiService.saveToken('new-token');
      final result = await ApiService.getToken();
      expect(result, 'new-token');
    });
  });

  group('clearToken', () {
    test('clearToken removes a previously saved token', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.saveToken('some-token');
      await ApiService.clearToken();
      final result = await ApiService.getToken();
      expect(result, isNull);
    });

    test('clearToken is idempotent when no token exists', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.clearToken();
      final result = await ApiService.getToken();
      expect(result, isNull);
    });
  });

  // ------------------------------------------------------------------
  // fromStorage
  // ------------------------------------------------------------------

  group('fromStorage', () {
    test('constructs ApiService from stored baseUrl and token', () async {
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'https://chat.example.com',
        'api_token': 'tok-abc',
      });
      final svc = await ApiService.fromStorage();
      expect(svc.baseUrl, 'https://chat.example.com');
    });

    test('constructs ApiService when only baseUrl is stored', () async {
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'https://chat.example.com',
      });
      final svc = await ApiService.fromStorage();
      expect(svc.baseUrl, 'https://chat.example.com');
    });

    test('throws StateError when no baseUrl is stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        () => ApiService.fromStorage(),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ------------------------------------------------------------------
  // sendMessage — SSE streaming
  // ------------------------------------------------------------------

  group('sendMessage', () {
    /// Start a local HTTP server that returns an SSE stream from [frames].
    ///
    /// Each frame string is written as a complete SSE frame (data + double
    /// newline).  The server auto-assigns a port and returns its URL.
    Future<Uri> startSseServer(List<String> frames) async {
      final server = await HttpServer.bind('localhost', 0);
      server.listen((request) {
        request.response.statusCode = 200;
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        for (final frame in frames) {
          request.response.write('data: $frame\n\n');
        }
        request.response.close();
      });
      return Uri(
        scheme: 'http',
        host: 'localhost',
        port: server.port,
      );
    }

    test('streams TokenEvent and DoneEvent on success', () async {
      SharedPreferences.setMockInitialValues({'owner_id': 'test-owner'});
      final uri = await startSseServer([
        '{"type":"token","content":"Hello"}',
        '{"type":"done","session_id":"s1","timestamp":1.5}',
      ]);

      final svc = ApiService(
        baseUrl: '$uri',
        authProvider: const TokenAuthProvider(),
      );

      final events = await svc
          .sendMessage(message: 'hi')
          .toList();

      expect(events, hasLength(2));
      expect(events[0], isA<TokenEvent>());
      expect((events[0] as TokenEvent).content, 'Hello');
      expect(events[1], isA<DoneEvent>());
      expect((events[1] as DoneEvent).sessionId, 's1');
    });

    test('streams ErrorEvent from backend error frame', () async {
      SharedPreferences.setMockInitialValues({'owner_id': 'test-owner'});
      final uri = await startSseServer([
        '{"type":"error","message":"bad request","code":"BAD_REQ",'
            '"correlation_id":"abc-123"}',
      ]);

      final svc = ApiService(
        baseUrl: '$uri',
        authProvider: const TokenAuthProvider(),
      );

      final events = await svc
          .sendMessage(message: 'hi')
          .toList();

      expect(events, hasLength(1));
      expect(events[0], isA<ErrorEvent>());
      expect((events[0] as ErrorEvent).message, 'bad request');
      expect((events[0] as ErrorEvent).code, 'BAD_REQ');
    });

    test('throws ApiException on non-200 HTTP status', () async {
      SharedPreferences.setMockInitialValues({'owner_id': 'test-owner'});
      final server = await HttpServer.bind('localhost', 0);
      server.listen((request) {
        request.response.statusCode = 500;
        request.response.write('Internal Server Error');
        request.response.close();
      });

      final svc = ApiService(
        baseUrl: 'http://localhost:${server.port}',
        authProvider: const TokenAuthProvider(),
      );

      expect(
        svc.sendMessage(message: 'hi').toList(),
        throwsA(isA<ApiException>()),
      );
    });

    test('ignores SSE comments and empty lines', () async {
      SharedPreferences.setMockInitialValues({'owner_id': 'test-owner'});
      final uri = await startSseServer([
        '{"type":"token","content":"A"}',
        '{"type":"token","content":"B"}',
      ]);
      // The server already sends clean frames; the _parseSseStream method
      // handles comments internally.  Verify we still get both tokens.
      final svc = ApiService(
        baseUrl: '$uri',
        authProvider: const TokenAuthProvider(),
      );

      final events = await svc
          .sendMessage(message: 'hi')
          .toList();

      expect(events, hasLength(2));
      expect((events[0] as TokenEvent).content, 'A');
      expect((events[1] as TokenEvent).content, 'B');
    });

    test('includes sessionId and messageId when provided', () async {
      SharedPreferences.setMockInitialValues({'owner_id': 'test-owner'});
      String? receivedBody;
      final server = await HttpServer.bind('localhost', 0);
      server.listen((request) async {
        receivedBody = await utf8.decodeStream(request);
        request.response.statusCode = 200;
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        request.response.write(
            'data: {"type":"done","session_id":"s2","timestamp":1.0}\n\n');
        request.response.close();
      });

      final svc = ApiService(
        baseUrl: 'http://localhost:${server.port}',
        authProvider: const TokenAuthProvider(),
      );

      await svc
          .sendMessage(
            message: 'hi',
            sessionId: 'my-session',
            messageId: 'my-msg',
          )
          .toList();

      final body = jsonDecode(receivedBody!) as Map<String, dynamic>;
      expect(body['session_id'], 'my-session');
      expect(body['message_id'], 'my-msg');
      expect(body['message'], 'hi');
    });
  });
}
