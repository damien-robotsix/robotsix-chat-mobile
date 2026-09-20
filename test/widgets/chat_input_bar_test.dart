import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/widgets/chat_input_bar.dart';

void main() {
  testWidgets('renders the hint text and send icon', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInputBar(
          controller: controller,
          isLoading: false,
          onSend: () {},
        ),
      ),
    ));

    expect(find.widgetWithText(TextField, 'Type a message...'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('tapping send invokes onSend when not loading', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sent = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInputBar(
          controller: controller,
          isLoading: false,
          onSend: () => sent++,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.send));
    expect(sent, 1);
  });

  testWidgets('send button is disabled while loading', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInputBar(
          controller: controller,
          isLoading: true,
          onSend: () {},
        ),
      ),
    ));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}
