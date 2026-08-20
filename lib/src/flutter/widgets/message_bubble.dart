import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import 'citation_chips.dart';
import 'inline_markdown.dart';

/// One message, aligned by role and coloured from the ambient theme.
class MessageBubble extends StatelessWidget {
  /// Creates a bubble.
  const MessageBubble({required this.message, this.onCitationTap, super.key});

  /// The message to render.
  final ChatMessage message;

  /// Called with the source the reader tapped. When null the citations render
  /// as plain, non-interactive chips.
  final ValueChanged<Citation>? onCitationTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final baseStyle = DefaultTextStyle.of(context).style.copyWith(
          color: isUser ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );

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
              color: isUser
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            // SelectableText.rich, not SelectableText: replies arrive as
            // Markdown, and printing the raw string shows `**bold**` verbatim.
            child: SelectableText.rich(
              TextSpan(
                children: inlineMarkdownSpans(message.text, baseStyle),
              ),
            ),
          ),
          if (message.citations.isNotEmpty)
            CitationChips(
              citations: message.citations,
              onTap: onCitationTap,
            ),
        ],
      ),
    );
  }
}
