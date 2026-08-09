import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';

/// Settings screen for configuring the backend connection.
///
/// Persists the backend base URL and API token via [ApiService]'s
/// storage helpers so settings survive app restarts.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController(text: 'https://chat.example.com');
  final _tokenController = TextEditingController();

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
    final token = await ApiService.getToken();
    if (token != null && mounted) {
      setState(() {
        _tokenController.text = token;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ApiService.saveBaseUrl(_urlController.text.trim());
    final token = _tokenController.text.trim();
    if (token.isNotEmpty) {
      await ApiService.saveToken(token);
    } else {
      await ApiService.clearToken();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    Navigator.pop(context);
  }

  Future<void> _clearToken() async {
    await ApiService.clearToken();
    if (!mounted) return;
    setState(() {
      _tokenController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token cleared')),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Backend Base URL',
                hintText: 'https://chat.example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'API Token',
                hintText: 'Enter your API token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _checkForUpdate,
              icon: const Icon(Icons.system_update),
              label: const Text('Check for Updates'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearToken,
              icon: const Icon(Icons.logout),
              label: const Text('Clear Token'),
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
