import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/models/chat_session.dart';
import 'package:robotsix_chat_mobile/widgets/session_drawer.dart';
import 'package:robotsix_chat_mobile/widgets/session_tile.dart';

SessionDrawer _drawer({
  bool loading = false,
  String? error,
  List<ChatSession> sessions = const [],
  String? activeSessionId,
  VoidCallback? onRetry,
  VoidCallback? onCreateSession,
  void Function(String)? onSwitchSession,
  void Function(String)? onCloseSession,
  void Function(String)? onDeleteSession,
}) {
  return SessionDrawer(
    loading: loading,
    error: error,
    sessions: sessions,
    activeSessionId: activeSessionId,
    onRetry: onRetry ?? () {},
    onCreateSession: onCreateSession ?? () {},
    onSwitchSession: onSwitchSession ?? (_) {},
    onCloseSession: onCloseSession ?? (_) {},
    onDeleteSession: onDeleteSession ?? (_) {},
  );
}

void main() {
  testWidgets('shows a spinner while loading', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _drawer(loading: true)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error and retry invokes onRetry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      home: _drawer(error: 'boom', onRetry: () => retried++),
    ));

    expect(find.text('Failed to load sessions'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('shows the empty state when there are no sessions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: _drawer()));
    expect(find.text('No sessions yet.'), findsOneWidget);
    expect(find.text('Create one'), findsOneWidget);
  });

  testWidgets('renders a SessionTile per session', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _drawer(
        sessions: const [
          ChatSession(sessionId: 's1', title: 'First', turnCount: 2),
          ChatSession(sessionId: 's2', title: 'Second'),
        ],
        activeSessionId: 's1',
      ),
    ));

    expect(find.byType(SessionTile), findsNWidgets(2));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('2 turns'), findsOneWidget);
  });

  testWidgets('delete menu action invokes onDeleteSession', (tester) async {
    String? deleted;
    await tester.pumpWidget(MaterialApp(
      home: _drawer(
        sessions: const [ChatSession(sessionId: 's1', title: 'First')],
        onDeleteSession: (id) => deleted = id,
      ),
    ));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, 's1');
  });
}
