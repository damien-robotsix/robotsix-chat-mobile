import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/update_service.dart';

/// Settings screen for configuring the backend connection and
/// managing authentication.
///
/// Persists the backend base URL via [ApiService]'s storage helpers
/// so settings survive app restarts.  Authentication is handled
/// through the fleet SSO (tinyauth) login flow — see
/// [OidcTokenExchangeAuthProvider.startSsoLogin].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController(text: 'https://chat.example.com');
  bool _isLoggedIn = false;
  StreamSubscription<bool>? _authSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _authSub = OidcTokenExchangeAuthProvider.authStateChanges.listen((v) {
      if (mounted) setState(() => _isLoggedIn = v);
    });
  }

  Future<void> _loadSettings() async {
    final url = await ApiService.getBaseUrl();
    if (url != null && url.isNotEmpty && mounted) {
      setState(() {
        _urlController.text = url;
      });
    }
    final token = await OidcTokenExchangeAuthProvider.getSubjectToken();
    if (mounted) {
      setState(() {
        _isLoggedIn = token != null && token.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ApiService.saveBaseUrl(_urlController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    Navigator.pop(context);
  }

  Future<void> _login() async {
    final baseUrl = _urlController.text.trim();
    if (baseUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a Backend Base URL first.'),
        ),
      );
      return;
    }
    await ApiService.saveBaseUrl(baseUrl);
    final ok = await OidcTokenExchangeAuthProvider.startSsoLogin(baseUrl);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the login page.'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Clear your stored credentials?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await OidcTokenExchangeAuthProvider.clearSubjectToken();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged out.')),
    );
  }

  Future<void> _checkForUpdate() async {
    try {
      final result = await UpdateService().checkForUpdate();
      if (!mounted) return;
      switch (result.status) {
        case UpdateStatus.updateAvailable:
          showUpdateDialog(context, result);
        case UpdateStatus.upToDate:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Up to date (v${result.currentVersion})'),
            ),
          );
        case UpdateStatus.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Update check failed: ${result.errorMessage}'),
            ),
          );
      }
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update check failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('server_url_field'),
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Backend Base URL',
                hintText: 'https://chat.example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            // ---------- Auth status card ----------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isLoggedIn ? Icons.check_circle : Icons.error_outline,
                          color: _isLoggedIn
                              ? Colors.green.shade700
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isLoggedIn ? 'Authenticated' : 'Not authenticated',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isLoggedIn)
                      OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Log out'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _login,
                        icon: const Icon(Icons.login),
                        label: const Text('Log in with SSO'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _checkForUpdate,
              icon: const Icon(Icons.system_update),
              label: const Text('Check for Updates'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}