import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/screens/chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'home screen renders the chat title, empty state, input, and settings action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    // AppBar carries the app name.
    expect(find.widgetWithText(AppBar, 'robotsix-chat'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    // Drawer menu icon is present.
    expect(find.byIcon(Icons.menu), findsOneWidget);

    // Empty conversation state.
    expect(
      find.widgetWithText(
        Center,
        'No messages yet.\nType below to start chatting.',
      ),
      findsOneWidget,
    );

    // Message input and send action.
    expect(find.widgetWithText(TextField, 'Type a message...'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('session bar is shown (no session state)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No session'), findsOneWidget);
  });

  testWidgets('drawer is present with sessions header', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    // Open the drawer
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Sessions'), findsOneWidget);
  });
}
