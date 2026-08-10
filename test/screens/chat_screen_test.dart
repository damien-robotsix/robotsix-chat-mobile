import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/screens/chat_screen.dart';

void main() {
  group('ChatScreen', () {
    setUp(() {
      // Provide a base URL so ApiService.fromStorage() doesn't throw.
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'https://chat.example.com',
        'api_token': 'test-token',
      });
      // Prevent _checkForUpdate from hitting real platform channels.
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '1',
      );
    });

    testWidgets('renders empty-state message when no messages exist',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      // Render one frame — the empty state is visible immediately.
      expect(
        find.text('No messages yet.\nType below to start chatting.'),
        findsOneWidget,
      );
    });

    testWidgets('renders text input field', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('text field accepts user input', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));

      await tester.enterText(find.byType(TextField), 'Hello, world!');
      await tester.pump();

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('send button is present', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('send button triggers loading state', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));

      // Enter a message.
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      // Tap send — _sendMessage clears the field and sets _isLoading
      // synchronously via setState before any async work starts.
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // The text field should now be empty.
      expect(find.text('Hello'), findsNothing);

      // The send button is replaced by a CircularProgressIndicator.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('message list renders user message after send', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));

      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // A user message bubble should appear in the list.
      expect(find.text('Test message'), findsOneWidget);
    });

    testWidgets('settings icon button is present in the AppBar',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });
}
