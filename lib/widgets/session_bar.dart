import 'package:flutter/material.dart';

/// A compact bar showing the current session id (or "No session") with a
/// shortcut to start a new session.
class SessionBar extends StatelessWidget {
  const SessionBar({
    super.key,
    required this.sessionId,
    required this.onNewSession,
  });

  final String? sessionId;
  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) {
    final id = sessionId;
    final label = id != null
        ? 'Session: ${id.length > 12 ? id.substring(0, 12) : id}...'
        : 'No session';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            id != null ? Icons.chat_bubble : Icons.chat_bubble_outline,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New session',
            onPressed: onNewSession,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
