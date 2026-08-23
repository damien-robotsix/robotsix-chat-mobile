import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('server URL field is rendered exactly once', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final urlFieldFinder = find.byKey(const Key('server_url_field'));
    expect(urlFieldFinder, findsOneWidget);

    final urlField = tester.widget<TextField>(urlFieldFinder);
    expect(urlField.controller!.text, 'https://chat.example.com');
  });

  testWidgets('shows not-authenticated state by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Not authenticated'), findsOneWidget);
    expect(find.text('Log in with SSO'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
  });

  testWidgets('does not show free-form API token field', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('API Token'), findsNothing);
    expect(find.text('Clear Token'), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing); // not shown when logged out
  });

  testWidgets('save and check-for-updates buttons are present',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Check for Updates'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}