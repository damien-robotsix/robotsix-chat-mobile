import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/screens/settings_screen.dart';
import 'package:robotsix_chat_mobile/services/api_service.dart';

void main() {
  group('SettingsScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Prevent _checkForUpdate from hitting real platform channels.
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    testWidgets('URL field renders pre-filled with default', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump(); // Let async _loadSettings complete

      expect(find.text('https://chat.example.com'), findsOneWidget);
    });

    testWidgets('token field renders', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      // The token field uses obscureText, and the label text is shown
      // when the field is empty.
      expect(find.text('API Token'), findsOneWidget);
    });

    testWidgets('save button is present', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Clear Token button is present', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      expect(find.text('Clear Token'), findsOneWidget);
    });

    testWidgets('Check for Updates button is present', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('submitting valid values persists URL and token', (tester) async {
      // Use a navigator with two routes so Navigator.pop succeeds.
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: Center(child: Text('Home'))),
          '/settings': (_) => const SettingsScreen(),
        },
      ));

      // Navigate to settings.
      Navigator.of(tester.element(find.text('Home'))).pushNamed('/settings');
      await tester.pumpAndSettle();

      // Enter URL and token.
      await tester.enterText(
        find.byType(TextField).at(0),
        'https://mybackend.example.com',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'my-secret-token',
      );
      await tester.pump();

      // Tap Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // After save + pop, we should be back on the Home screen.
      expect(find.text('Home'), findsOneWidget);

      // The saved values should be persisted.
      final url = await ApiService.getBaseUrl();
      expect(url, 'https://mybackend.example.com');
      final token = await ApiService.getToken();
      expect(token, 'my-secret-token');
    });

    testWidgets('saving with empty token calls clearToken', (tester) async {
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: Center(child: Text('Home'))),
          '/settings': (_) => const SettingsScreen(),
        },
      ));

      // Pre-populate token storage.
      SharedPreferences.setMockInitialValues({
        'api_token': 'old-token',
      });

      Navigator.of(tester.element(find.text('Home'))).pushNamed('/settings');
      await tester.pumpAndSettle();

      // Enter URL but leave token empty.
      await tester.enterText(
        find.byType(TextField).at(0),
        'https://mybackend.example.com',
      );
      await tester.pump();

      // Tap Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Token should be cleared.
      final token = await ApiService.getToken();
      expect(token, isNull);
    });

    testWidgets('URL field accepts user input', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      // Clear the default URL and type a new one.
      await tester.enterText(
        find.byType(TextField).at(0),
        'https://custom.example.com',
      );
      await tester.pump();

      expect(find.text('https://custom.example.com'), findsOneWidget);
    });

    testWidgets('token field is obscured', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      // Find EditableText with obscureText true.
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      final tokenField = textFields.last;
      expect(tokenField.obscureText, isTrue);
    });
  });
}
