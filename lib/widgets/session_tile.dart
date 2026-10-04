import 'package:flutter/material.dart';

import '../models/chat_session.dart';

/// A single session entry in the sessions drawer list.
///
/// Renders the session title/turn count and a popup menu exposing the close
/// and delete actions. All actions are delegated to the parent via callbacks.
class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.onDelete,
  });

  final ChatSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: isActive,
      leading: Icon(isActive ? Icons.chat_bubble : Icons.chat_bubble_outline),
      title: Text(
        session.title ??
            '${session.sessionId.length > 16 ? session.sessionId.substring(0, 16) : session.sessionId}...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: session.turnCount != null
          ? Text('${session.turnCount} turns')
          : null,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          if (action == 'delete') {
            onDelete();
          } else if (action == 'close') {
            onClose();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'close', child: Text('Close')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
