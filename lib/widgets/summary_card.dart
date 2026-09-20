import 'package:flutter/material.dart';

/// Compact summary card shown by default when a conversation has messages.
/// Tapping it (or its button) expands to the full transcript via [onExpand].
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.messageCount,
    required this.lastMessageText,
    required this.onExpand,
  });

  final String title;
  final int messageCount;
  final String? lastMessageText;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final lastText = lastMessageText;
    return Center(
      child: SingleChildScrollView(
        child: Card(
          margin: const EdgeInsets.all(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onExpand,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.article_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$messageCount message${messageCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (lastText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      lastText,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onExpand,
                      icon: const Icon(Icons.unfold_more),
                      label: const Text('Show full transcript'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
