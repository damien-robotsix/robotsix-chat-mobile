import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import 'session_tile.dart';

/// The sessions drawer: a header with a "new session" shortcut plus the
/// loading / error / empty / list states for the available sessions.
///
/// All session state is passed in and every action is delegated to the parent
/// via callbacks, keeping this widget purely presentational.
class SessionDrawer extends StatelessWidget {
  const SessionDrawer({
    super.key,
    required this.loading,
    required this.error,
    required this.sessions,
    required this.activeSessionId,
    required this.onRetry,
    required this.onCreateSession,
    required this.onSwitchSession,
    required this.onCloseSession,
    required this.onDeleteSession,
  });

  final bool loading;
  final String? error;
  final List<ChatSession> sessions;
  final String? activeSessionId;
  final VoidCallback onRetry;
  final VoidCallback onCreateSession;
  final void Function(String sessionId) onSwitchSession;
  final void Function(String sessionId) onCloseSession;
  final void Function(String sessionId) onDeleteSession;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 12),
                  Text(
                    'Sessions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'New session',
                    onPressed: () {
                      Navigator.pop(context); // close drawer
                      onCreateSession();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Failed to load sessions',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: onRetry,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : sessions.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('No sessions yet.'),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      onCreateSession();
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Create one'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: sessions.length,
                              itemBuilder: (context, index) {
                                final session = sessions[index];
                                final isActive =
                                    session.sessionId == activeSessionId;
                                return SessionTile(
                                  session: session,
                                  isActive: isActive,
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (!isActive) {
                                      onSwitchSession(session.sessionId);
                                    }
                                  },
                                  onClose: () =>
                                      onCloseSession(session.sessionId),
                                  onDelete: () =>
                                      onDeleteSession(session.sessionId),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
