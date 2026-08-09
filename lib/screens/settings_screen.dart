import 'package:flutter/material.dart';

import '../main.dart';
import '../services/update_service.dart';

/// Settings screen for configuring the backend connection.
///
/// Stores the backend base URL and API token.  Currently held in-memory
/// during the session; persistent storage (e.g. flutter_secure_storage)
/// will be added in a future iteration.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController(text: 'https://chat.example.com');
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved (in-memory)')),
    );
    Navigator.pop(context);
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
