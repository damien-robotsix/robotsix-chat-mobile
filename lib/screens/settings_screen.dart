import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/update_service.dart';

/// Settings screen for configuring the backend connection.
///
/// Persists the backend base URL via [ApiService]'s storage helpers
/// so settings survive app restarts.  Authentication is handled by
/// [TokenExchangeAuthProvider] — the user logs in via fleet SSO
/// rather than manually typing a token.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController(text: 'https://chat.example.com');

  bool _isLoggedIn = false;
  bool _isLoggingIn = false;
  String _authStatus = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final url = await ApiService.getBaseUrl();
    if (url != null && url.isNotEmpty && mounted) {
      setState(() {
        _urlController.text = url;
      });
    }
    final provider = ApiService.currentAuthProvider;
    if (provider is TokenExchangeAuthProvider && mounted) {
      final loggedIn = await provider.isLoggedIn;
      final token = await provider.getToken();
      setState(() {
        _isLoggedIn = loggedIn;
        _authStatus = loggedIn
            ? 'Logged in (token: ${_maskToken(token ?? '')})'
            : 'Not logged in';
      });
    }
  }

  String _maskToken(String token) {
    if (token.length <= 8) return '***';
    return '${token.substring(0, 4)}…${token.substring(token.length - 4)}';
  }

  @override
  void dispose() {
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
    final provider = ApiService.currentAuthProvider;
    if (provider is! TokenExchangeAuthProvider) return;

    setState(() => _isLoggingIn = true);

    try {
      final launched = await provider.startLogin();
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open login page')),
        );
      }
      // The deep-link callback will handle token exchange and storage.
      // Poll briefly for the result.
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        final loggedIn = await provider.isLoggedIn;
        if (loggedIn) {
          setState(() {
            _isLoggedIn = true;
            _isLoggingIn = false;
            _authStatus = 'Logged in';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Login successful')),
            );
          }
          return;
        }
      }
      if (mounted) {
        setState(() => _isLoggingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login timed out. Please try again.')),
        );
      }
    } on Exception {
      if (mounted) {
        setState(() => _isLoggingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final provider = ApiService.currentAuthProvider;
    if (provider is TokenExchangeAuthProvider) {
      await provider.clearToken();
      setState(() {
        _isLoggedIn = false;
        _authStatus = 'Not logged in';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out')),
      );
    }
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
            // Auth status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isLoggedIn ? Icons.lock_open : Icons.lock_outline,
                          color: _isLoggedIn ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _authStatus.isNotEmpty
                                ? _authStatus
                                : 'Checking…',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isLoggedIn)
                      OutlinedButton.icon(
                        onPressed: _isLoggingIn ? null : _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Log Out'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _isLoggingIn ? null : _login,
                        icon: _isLoggingIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(_isLoggingIn ? 'Logging in…' : 'Log In'),
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