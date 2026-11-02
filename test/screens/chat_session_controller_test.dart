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
  });

  test('titleOf returns the known title or null', () async {
    when(() => api.listSessions()).thenAnswer((_) async => [_session]);
    await controller.loadSessions();

    expect(controller.titleOf('s-1'), 'First');
    expect(controller.titleOf('other'), isNull);
    expect(controller.titleOf(null), isNull);
  });
}
