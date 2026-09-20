import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/widgets/summary_card.dart';

void main() {
  testWidgets('renders title, message count and last message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SummaryCard(
          title: 'My chat',
          messageCount: 3,
          lastMessageText: 'hello there',
          onExpand: () {},
        ),
      ),
    ));

    expect(find.text('My chat'), findsOneWidget);
    expect(find.text('3 messages'), findsOneWidget);
    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('Show full transcript'), findsOneWidget);
  });

  testWidgets('uses singular "message" for a single message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SummaryCard(
          title: 'My chat',
          messageCount: 1,
          lastMessageText: null,
          onExpand: () {},
        ),
      ),
    ));

    expect(find.text('1 message'), findsOneWidget);
  });

  testWidgets('tapping the expand button invokes onExpand', (tester) async {
    var expanded = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SummaryCard(
          title: 'My chat',
          messageCount: 2,
          lastMessageText: 'hi',
          onExpand: () => expanded++,
        ),
      ),
    ));

    await tester.tap(find.text('Show full transcript'));
    expect(expanded, 1);
  });
}
