import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'services/update_service.dart';

void main() {
  runApp(const RobotsixChatApp());
}

/// Show an update-available dialog and offer to install.
Future<void> showUpdateDialog(BuildContext context, UpdateCheckResult result) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Update Available'),
      content: Text(
        'Version ${result.latestVersion} is available '
        '(you have ${result.currentVersion}).\n\n'
        'Install now?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            final url = result.apkDownloadUrl;
            if (url != null) {
              UpdateService().downloadAndInstall(url);
            }
          },
          child: const Text('Install'),
        ),
      ],
    ),
  );
}

class RobotsixChatApp extends StatelessWidget {
  const RobotsixChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'robotsix-chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const ChatScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
