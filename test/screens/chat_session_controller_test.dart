import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:robotsix_chat_mobile/models/api_exception.dart';
import 'package:robotsix_chat_mobile/models/chat_session.dart';
import 'package:robotsix_chat_mobile/screens/chat_session_controller.dart';
import 'package:robotsix_chat_mobile/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

const _session = ChatSession(sessionId: 's-1', title: 'First');

void main() {
  late MockApiService api;
  late int authExpiredCalls;
  late ChatSessionController controller;

  setUp(() {
    api = MockApiService();
    authExpiredCalls = 0;
    controller = ChatSessionController(
      apiProvider: () => api,
      onAuthExpired: () => authExpiredCalls++,
    );
  });

  tearDown(() => controller.dispose());

  group('describeSessionError', () {
    test('uses the ApiException display message', () {
      expect(describeSessionError(const ApiException(500, 'boom')), 'boom');
    });

    test('uses the AuthException display message', () {
      expect(
        describeSessionError(const AuthException(401, 'raw')),
        const AuthException(401, 'raw').message,
      );
    });

    test('falls back to toString for other errors', () {
      expect(describeSessionError(StateError('x')), '${StateError('x')}');
    });
  });

  group('loadSessions', () {
    test('stores the sessions and clears loading', () async {
      when(() => api.listSessions()).thenAnswer((_) async => [_session]);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.loadSessions();

      expect(controller.sessions, [_session]);
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
      expect(notifications, 2);
    });

    test('captures API errors without prompting re-login', () async {
      when(() => api.listSessions()).thenThrow(const ApiException(500, 'down'));

      await controller.loadSessions();

      expect(controller.error, 'down');
      expect(controller.loading, isFalse);
      expect(authExpiredCalls, 0);
    });

    test('reports expired auth through onAuthExpired', () async {
      when(
        () => api.listSessions(),
      ).thenThrow(const AuthException(401, 'expired'));

      await controller.loadSessions();

      expect(controller.error, const AuthException(401, 'x').message);
      expect(authExpiredCalls, 1);
    });

    test('is a no-op without an API client', () async {
      final idle = ChatSessionController(apiProvider: () => null);
      await idle.loadSessions();
      expect(idle.sessions, isEmpty);
      expect(idle.loading, isFalse);
      idle.dispose();
    });
  });

  group('CRUD', () {
    setUp(() {
      when(() => api.listSessions()).thenAnswer((_) async => [_session]);
    });

    test('createSession returns the session and refreshes', () async {
      when(() => api.createSession()).thenAnswer((_) async => _session);

      final created = await controller.createSession();
      await pumpEventQueue();

      expect(created, _session);
      verify(() => api.listSessions()).called(1);
    });

    test('deleteSession deletes and refreshes', () async {
      when(() => api.deleteSession('s-1')).thenAnswer((_) async {});

      expect(await controller.deleteSession('s-1'), isTrue);
      await pumpEventQueue();

      verify(() => api.deleteSession('s-1')).called(1);
      verify(() => api.listSessions()).called(1);
    });

    test('closeSession rethrows API failures', () async {
      when(
        () => api.closeSession('s-1'),
      ).thenThrow(const ApiException(409, 'busy'));

      await expectLater(
        controller.closeSession('s-1'),
        throwsA(isA<ApiException>()),
      );
      verifyNever(() => api.listSessions());
    });

    test('closeSession closes and refreshes', () async {
      when(() => api.closeSession('s-1')).thenAnswer((_) async {});

      await controller.closeSession('s-1');
      await pumpEventQueue();

      verify(() => api.closeSession('s-1')).called(1);
      verify(() => api.listSessions()).called(1);
    });

    test('createSession rethrows API failures without refreshing', () async {
      when(() => api.createSession()).thenThrow(const ApiException(500, 'no'));

      await expectLater(
        controller.createSession(),
        throwsA(isA<ApiException>()),
      );
      verifyNever(() => api.listSessions());
    });

    test('deleteSession rethrows auth failures without refreshing', () async {
      when(
        () => api.deleteSession('s-1'),
      ).thenThrow(const AuthException(401, 'expired'));

      await expectLater(
        controller.deleteSession('s-1'),
        throwsA(isA<AuthException>()),
      );
      verifyNever(() => api.listSessions());
    });
  });

  group('without an API client', () {
    late ChatSessionController idle;

    setUp(() => idle = ChatSessionController(apiProvider: () => null));
    tearDown(() => idle.dispose());

    test('createSession returns null', () async {
      expect(await idle.createSession(), isNull);
    });

    test('deleteSession returns false', () async {
      expect(await idle.deleteSession('s-1'), isFalse);
    });

    test('closeSession completes without error', () async {
      await idle.closeSession('s-1');
      expect(idle.sessions, isEmpty);
    });

    test('fetchHistory returns an empty list', () async {
      expect(await idle.fetchHistory('s-1'), isEmpty);
    });
  });

  group('loadSessions empty state', () {
    test('an empty server list yields no sessions and no error', () async {
      when(() => api.listSessions()).thenAnswer((_) async => []);

      await controller.loadSessions();

      expect(controller.sessions, isEmpty);
      expect(controller.error, isNull);
      expect(controller.titleOf('s-1'), isNull);
    });

    test('a reload clears a previous error', () async {
      when(() => api.listSessions()).thenThrow(const ApiException(500, 'down'));
      await controller.loadSessions();
      expect(controller.error, 'down');

      when(() => api.listSessions()).thenAnswer((_) async => [_session]);
      await controller.loadSessions();

      expect(controller.error, isNull);
      expect(controller.sessions, [_session]);
    });
  });

  group('fetchHistory (switch session)', () {
    test('returns the history for the requested session', () async {
      final history = [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ];
      when(() => api.getHistory('s-1')).thenAnswer((_) async => history);

      expect(await controller.fetchHistory('s-1'), history);
      verify(() => api.getHistory('s-1')).called(1);
    });

    test('returns an empty history for a new session', () async {
      when(() => api.getHistory('s-1')).thenAnswer((_) async => []);

      expect(await controller.fetchHistory('s-1'), isEmpty);
    });

    test('rethrows API failures', () async {
      when(
        () => api.getHistory('s-1'),
      ).thenThrow(const ApiException(404, 'gone'));

      await expectLater(
        controller.fetchHistory('s-1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('titleOf returns the known title or null', () async {
    when(() => api.listSessions()).thenAnswer((_) async => [_session]);
    await controller.loadSessions();

    expect(controller.titleOf('s-1'), 'First');
    expect(controller.titleOf('other'), isNull);
    expect(controller.titleOf(null), isNull);
  });
}
