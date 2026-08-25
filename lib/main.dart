import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_provider.dart';
import 'services/update_service.dart';

/// Entry point for the robotsix-chat mobile app.
///
/// Initialises Flutter bindings, wires up the deep-link listener for
/// SSO callbacks, and runs the [RobotsixChatApp] widget.
void main() {
  runApp(const RobotsixChatApp());
  _initDeepLinks();
}

final _appLinks = AppLinks();

Future<void> _initDeepLinks() async {
  // Handle the link that launched the app (cold start).
  try {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      await _handleDeepLink(initialUri);
    }
  } catch (_) {
    // AppLinks may throw on platforms that don't support deep links —
    // treat as a no-op.
  }

  // Handle links that arrive while the app is already running.
  _appLinks.uriLinkStream.listen(
    _handleDeepLink,
    onError: (_) {
      // Deep-link processing failures are non-critical; the user can
      // still log in manually.
    },
  );
}

Future<void> _handleDeepLink(Uri uri) async {
  try {
    if (uri.scheme == 'robotsixchat' &&
        uri.host == 'auth' &&
        uri.path.startsWith('/callback')) {
      await OidcTokenExchangeAuthProvider.handleAuthCallback(uri);
    }
  } catch (_) {
    // Non-critical — the user can retry SSO login from Settings.
  }
}

/// Show an update-available dialog prompting the user to install a new
/// version.
///
/// [context] is the build context used to show the dialog.
/// [result] carries the latest version info including the version strings
/// and an optional APK download URL.  If the user taps "Install" and an
/// APK URL is present, the download-and-install flow is started via
/// [UpdateService].
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

/// Root [MaterialApp] widget for the robotsix-chat application.
///
/// Configures the app's theme, routes, and top-level navigation.
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
