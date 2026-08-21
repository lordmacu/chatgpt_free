import 'dart:convert';

import '../core/json_reply.dart';
import 'function_tool.dart';
import 'prompt.dart';

/// What one raw extractor reply turned out to be.
sealed class ToolEnvelope {
  const ToolEnvelope(this.notes);

  /// What had to be tolerated to read it — `fenced`, `prose-before`,
  /// `duplicate-marker`. Diagnostics, not errors.
  final List<String> notes;
}

/// The reply carried calls (possibly zero, for an explicit "no tool").
final class EnvelopeCalls extends ToolEnvelope {
  /// Creates it.
  const EnvelopeCalls(this.calls, super.notes);

  /// The calls, still raw — names and decoded arguments, not yet validated.
  final List<Map<String, dynamic>> calls;
}

/// The model reported a required parameter the request never stated.
final class EnvelopeNeedInfo extends ToolEnvelope {
  /// Creates it.
  const EnvelopeNeedInfo(this.function, this.missing, super.notes);

  /// The function it would have called.
  final String function;

  /// The parameters it could not fill.
  final List<String> missing;
}

/// The reply was not a well-formed envelope at all.
final class EnvelopeUnreadable extends ToolEnvelope {
  /// Creates it.
  const EnvelopeUnreadable(super.notes);
}

final RegExp _fence = RegExp(r'```[a-zA-Z]*\n?');

/// Reads the extractor's reply.
///
/// Tolerant on purpose: the model occasionally fences its output or repeats the
/// marker, and neither is worth spending a second upstream message to fix.
/// What it will not do is guess — a reply with no marker comes back
/// [EnvelopeUnreadable] so the caller can repair it.
ToolEnvelope parseToolEnvelope(String text) {
  final notes = <String>[];
  var t = text.trim();

  if (t.contains('```')) {
    notes.add('fenced');
    t = t.replaceAll(_fence, '').replaceAll('```', '').trim();
  }

  final hasCall = t.contains(kToolCallMarker);

  if (t.contains(kNeedInfoMarker) && !hasCall) {
    final payload = t.split(kNeedInfoMarker).last.trim();
    final decoded = _tryDecodeObject(payload);
    return EnvelopeNeedInfo(
      '${decoded?['function'] ?? ''}',
      [for (final m in (decoded?['missing'] as List? ?? const [])) '$m'],
      notes,
    );
  }

  if (t.contains(kNoToolMarker) && !hasCall) {
    return EnvelopeCalls(const [], notes);
  }

  if (!hasCall) return EnvelopeUnreadable([...notes, 'no-marker']);

  if (kToolCallMarker.allMatches(t).length > 1) notes.add('duplicate-marker');
  if (!t.startsWith(kToolCallMarker)) notes.add('prose-before');

  // Between the first marker and the next one, if the model repeated it.
  final payload =
      t.split(kToolCallMarker)[1].split(kToolCallMarker).first.trim();
  for (final candidate in [payload, extractJson(payload)]) {
    final decoded = _tryDecodeObject(candidate);
    final calls = decoded?['calls'];
    if (calls is List) {
      return EnvelopeCalls([
        for (final c in calls)
          if (c is Map) Map<String, dynamic>.from(c),
      ], notes);
    }
  }
  return EnvelopeUnreadable([...notes, 'invalid-json']);
}

Map<String, dynamic>? _tryDecodeObject(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// Turns raw envelope entries into [ToolCall]s, dropping anything nameless.
List<ToolCall> toToolCalls(List<Map<String, dynamic>> raw) => [
      for (final c in raw)
        if (c['name'] is String && (c['name'] as String).isNotEmpty)
          ToolCall(
            name: c['name'] as String,
            arguments: c['arguments'] is Map
                ? Map<String, dynamic>.from(c['arguments'] as Map)
                : <String, dynamic>{},
          ),
    ];
