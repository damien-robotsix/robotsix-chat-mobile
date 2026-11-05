import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:robotsix_chat_mobile/models/api_exception.dart';
import 'package:robotsix_chat_mobile/models/chat_session.dart';
import 'package:robotsix_chat_mobile/models/subsession.dart';
import 'package:robotsix_chat_mobile/screens/subsessions_screen.dart';
import 'package:robotsix_chat_mobile/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

const _expiredMessage = 'Session expired — log in again from Settings.';

const _watcher = Subsession(
  subsessionId: 'sub-1',
  kind: 'periodic',
  title: 'Watcher',
  status: 'running',
);

void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  void stubSessions(List<ChatSession> sessions) {
    when(() => api.listSessions()).thenAnswer((_) async => sessions);
  }

  void stubSubs(String sessionId, List<Subsession> subs) {
    when(() => api.listSubsessions(sessionId)).thenAnswer((_) async => subs);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    final app = MaterialApp(home: SubsessionsScreen(apiService: api));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Future<void> openCloseDialog(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Close subsession?'), findsOneWidget);
  }

  testWidgets('rows are sorted by lastActivityAt desc across sessions', (
    tester,
  ) async {
    stubSessions(const [
      ChatSession(sessionId: 's1', title: 'Chat One'),
      ChatSession(sessionId: 's2', title: 'Chat Two'),
    ]);
    stubSubs('s1', const [
      Subsession(subsessionId: 'a', title: 'Oldest', lastActivityAt: 100),
      Subsession(subsessionId: 'b', title: 'No activity'),
    ]);
    stubSubs('s2', const [
      Subsession(subsessionId: 'c', title: 'Newest', lastActivityAt: 300),
      Subsession(subsessionId: 'd', title: 'Middle', lastActivityAt: 200),
    ]);

    await pumpScreen(tester);

    expect(find.text('4 subsessions · 0 active'), findsOneWidget);
    const order = ['Newest', 'Middle', 'Oldest', 'No activity'];
    final ys = [for (final t in order) tester.getTopLeft(find.text(t)).dy];
    expect(ys, [...ys]..sort());
    expect(ys.toSet().length, ys.length);
  });

  testWidgets('parent title falls back to sessionId', (tester) async {
    stubSessions(const [ChatSession(sessionId: 'sess-xyz')]);
    stubSubs('sess-xyz', const [
      Subsession(subsessionId: 'a', title: 'Job', status: 'running'),
    ]);

    await pumpScreen(tester);

    expect(find.text('Task · running · sess-xyz'), findsOneWidget);
    expect(find.text('1 subsession · 1 active'), findsOneWidget);
  });

  testWidgets('a failing session still renders the other rows', (tester) async {
    const err = ApiException(500, 'kaboom');
    stubSessions(const [
      ChatSession(sessionId: 'bad', title: 'Broken'),
      ChatSession(sessionId: 'good', title: 'Healthy'),
    ]);
    when(() => api.listSubsessions('bad')).thenAnswer((_) => Future.error(err));
    stubSubs('good', const [Subsession(subsessionId: 'g', title: 'Survivor')]);

    await pumpScreen(tester);

    expect(find.text('Survivor'), findsOneWidget);
    expect(find.text('kaboom'), findsNothing);
    expect(find.text('1 subsession · 0 active'), findsOneWidget);
  });

  testWidgets('AuthException shows the session-expired message', (
    tester,
  ) async {
    const err = AuthException(401, 'unauthorized');
    when(() => api.listSessions()).thenAnswer((_) => Future.error(err));

    await pumpScreen(tester);

    expect(find.text(_expiredMessage), findsOneWidget);
    expect(find.text('unauthorized'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('ApiException shows its message', (tester) async {
    const err = ApiException(500, 'Internal server error');
    when(() => api.listSessions()).thenAnswer((_) => Future.error(err));

    await pumpScreen(tester);

    expect(find.text('Internal server error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('close flow', () {
    setUp(() {
      stubSessions(const [ChatSession(sessionId: 's1')]);
      stubSubs('s1', const [_watcher]);
    });

    testWidgets('cancel does not call closeSubsession', (tester) async {
      await pumpScreen(tester);
      await openCloseDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Close subsession?'), findsNothing);
      verifyNever(() => api.closeSubsession(any()));
      verify(() => api.listSessions()).called(1);
    });

    testWidgets('confirm closes then refreshes', (tester) async {
      when(() => api.closeSubsession('sub-1')).thenAnswer((_) async {});

      await pumpScreen(tester);
      verify(() => api.listSessions()).called(1);
      await openCloseDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();

      verify(() => api.closeSubsession('sub-1')).called(1);
      verify(() => api.listSessions()).called(1);
      expect(find.text('Closed "Watcher"'), findsOneWidget);
    });

    testWidgets('ApiException on close shows a failure snackbar', (
      tester,
    ) async {
      const err = ApiException(409, 'already closed');
      when(() => api.closeSubsession('sub-1')).thenAnswer((_) async {
        throw err;
      });

      await pumpScreen(tester);
      verify(() => api.listSessions()).called(1);
      await openCloseDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();

      verify(() => api.closeSubsession('sub-1')).called(1);
      verifyNever(() => api.listSessions());
      expect(find.text('Close failed: already closed'), findsOneWidget);
    });
  });
}
