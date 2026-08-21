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

    // The URL value also appears in the field's hint text, so bare-text
    // finders would match twice. Anchor to the field's Key instead.
    final urlFieldFinder = find.byKey(const Key('server_url_field'));
    expect(urlFieldFinder, findsOneWidget);

    final urlField = tester.widget<TextField>(urlFieldFinder);
    expect(urlField.controller!.text, 'https://chat.example.com');
  });
}
