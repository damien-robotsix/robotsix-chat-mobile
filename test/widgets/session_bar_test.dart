import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/widgets/session_bar.dart';

void main() {
  testWidgets('shows "No session" when sessionId is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SessionBar(sessionId: null, onNewSession: () {})),
      ),
    );

    expect(find.text('No session'), findsOneWidget);
  });

  testWidgets('shows a truncated session label when set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionBar(
            sessionId: 'abcdefghijklmnopqrstuvwxyz',
            onNewSession: () {},
          ),
        ),
      ),
    );

    expect(find.text('Session: abcdefghijkl...'), findsOneWidget);
  });

  testWidgets('tapping add invokes onNewSession', (tester) async {
    var created = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionBar(sessionId: null, onNewSession: () => created++),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    expect(created, 1);
  });
}
