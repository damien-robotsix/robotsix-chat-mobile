import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/screens/chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home screen renders the chat title, empty state, input, and settings action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    // There is no "Home" label; the AppBar carries the app name.
    expect(find.widgetWithText(AppBar, 'robotsix-chat'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    // Empty conversation state.
    expect(
      find.widgetWithText(
        Center,
        'No messages yet.\nType below to start chatting.',
      ),
      findsOneWidget,
    );

    // Message input and send action.
    expect(find.widgetWithText(TextField, 'Type a message…'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
