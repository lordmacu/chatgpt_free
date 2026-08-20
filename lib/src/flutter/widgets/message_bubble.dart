import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import 'citation_chips.dart';

/// One message, aligned by role and coloured from the ambient theme.
class MessageBubble extends StatelessWidget {
  /// Creates a bubble.
  const MessageBubble({required this.message, super.key});

  /// The message to render.
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(
              message.text,
              style: TextStyle(
                color: isUser
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (message.citations.isNotEmpty)
            CitationChips(citations: message.citations),
        ],
      ),
    );
  }
}
