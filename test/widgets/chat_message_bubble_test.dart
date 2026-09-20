import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/models/chat_message.dart';
import 'package:robotsix_chat_mobile/widgets/chat_message_bubble.dart';

void main() {
  testWidgets('renders the message text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatMessageBubble(
          message: ChatMessage(
            id: '1',
            text: 'a reply',
            isUser: false,
            timestamp: DateTime(2020),
          ),
        ),
      ),
    ));

    expect(find.text('a reply'), findsOneWidget);
  });

  testWidgets('aligns user messages to the right', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatMessageBubble(
          message: ChatMessage(
            id: '1',
            text: 'from me',
            isUser: true,
            timestamp: DateTime(2020),
          ),
        ),
      ),
    ));

    final align = tester.widget<Align>(find.byType(Align));
    expect(align.alignment, Alignment.centerRight);
  });
}
