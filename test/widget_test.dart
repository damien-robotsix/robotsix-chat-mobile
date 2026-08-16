import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/main.dart';

void main() {
  testWidgets('App starts and renders chat screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );

    await tester.pumpWidget(const RobotsixChatApp());

    // The app title should be visible in the AppBar.
    expect(find.text('robotsix-chat'), findsOneWidget);

    // The placeholder text should appear when no messages exist.
    expect(find.text('No messages yet.\nType below to start chatting.'),
        findsOneWidget);

    // The settings gear icon should be present.
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
