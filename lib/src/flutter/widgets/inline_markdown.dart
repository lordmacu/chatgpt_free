import 'package:flutter/material.dart';

/// Renders the small slice of Markdown that actually shows up in chat replies.
///
/// The backend answers in Markdown, so a bubble that prints the raw string
/// shows `**like this**` to the user. This converts the inline constructs that
/// appear in practice — bold, italic, inline code, and heading lines — into
/// styled spans.
///
/// Deliberately NOT a Markdown renderer. Tables, images, links, block quotes
/// and fenced code blocks are left as-is: they are rare in a chat reply, and
/// supporting them properly means a parser and a dependency this package does
/// not want. If you need full Markdown, build your own bubble around
/// [ChatMessage.text] with the renderer of your choice.
List<TextSpan> inlineMarkdownSpans(String text, TextStyle? base) {
  final spans = <TextSpan>[];
  for (final (index, line) in text.split('\n').indexed) {
    if (index > 0) spans.add(const TextSpan(text: '\n'));
    spans.addAll(_lineSpans(line, base));
  }
  return spans;
}

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');

// Ordered by precedence: code first so its contents are never re-parsed, then
// the two-character markers before their one-character counterparts, or `**x**`
// would match the italic rule and leave stray asterisks behind.
final RegExp _inline = RegExp(
  r'`([^`]+)`'
  r'|\*\*([^*]+)\*\*'
  r'|__([^_]+)__'
  r'|\*([^*]+)\*'
  r'|(?<![A-Za-z0-9])_([^_]+)_(?![A-Za-z0-9])',
);

List<TextSpan> _lineSpans(String line, TextStyle? base) {
  final heading = _heading.firstMatch(line);
  if (heading != null) {
    // Headings become bold text rather than a larger size: a chat bubble that
    // suddenly grows a 24pt line reads as broken, not as structure.
    return _spansFor(heading.group(2) ?? '',
        (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold));
  }
  return _spansFor(line, base);
}

List<TextSpan> _spansFor(String text, TextStyle? base) {
  final spans = <TextSpan>[];
  var cursor = 0;

  for (final m in _inline.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
    }

    final code = m.group(1);
    final bold = m.group(2) ?? m.group(3);
    final italic = m.group(4) ?? m.group(5);

    if (code != null) {
      spans.add(TextSpan(
        text: code,
        style: (base ?? const TextStyle()).copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier New'],
        ),
      ));
    } else if (bold != null) {
      spans.add(TextSpan(
        text: bold,
        style:
            (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold),
      ));
    } else if (italic != null) {
      spans.add(TextSpan(
        text: italic,
        style:
            (base ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic),
      ));
    }

    cursor = m.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return spans;
}
