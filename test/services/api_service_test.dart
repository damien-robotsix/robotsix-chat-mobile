import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

/// Stub [AuthProvider] that returns a fixed set of headers.
class StubAuthProvider implements AuthProvider {
  final Map<String, String> headers;
  const StubAuthProvider(this.headers);

  @override
  Future<Map<String, String>> requestHeaders() async => headers;
}

void main() {
  group('ApiService', () {
    test('can be constructed with baseUrl and authProvider', () {
      final svc = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: const StubAuthProvider({}),
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

  group('StubAuthProvider', () {
    test('returns provided headers', () async {
      const provider = StubAuthProvider({'X-Custom': 'val'});
      final headers = await provider.requestHeaders();
      expect(headers['X-Custom'], 'val');
    });

    test('returns empty map when given empty map', () async {
      const provider = StubAuthProvider({});
      final headers = await provider.requestHeaders();
      expect(headers, isEmpty);
    });
  });
}