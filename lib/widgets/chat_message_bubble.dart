import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// A single chat message rendered as an aligned, coloured bubble.
///
/// User messages align right with the primary container colour; agent
/// messages align left with a surface container colour.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Align(
        alignment: message.isUser
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.isUser
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(message.text),
        ),
      ),
    );
  }
}
