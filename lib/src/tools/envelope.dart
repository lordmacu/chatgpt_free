import 'dart:convert';

import '../core/json_reply.dart';
import 'detect.dart';
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

  /// The calls, already name-checked against the allow-list and repaired
  /// against their schemas.
  final List<ToolCall> calls;
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

/// Reads the extractor's reply, in two layers.
///
/// The MARKERS are ours and explicit: the prompt asks for exactly one of
/// three, so [kNeedInfoMarker] and [kNoToolMarker] are read first and decide
/// outright. They have no equivalent in any model's native dialect — "no
/// function fits" and "a required parameter was never stated" are answers this
/// design asks for, not shapes a model happens to emit.
///
/// Everything else goes through [detectToolCalls], which reads a call out of
/// any dialect a prompted model actually produces. Before that layer, every
/// one of those cost a repair round trip — one more message off an anonymous
/// hourly allowance.
///
/// [validNames] is the allow-list AFTER a [ToolChoice] has narrowed it: pass
/// the raw declared set and a pinned choice becomes a suggestion the model can
/// ignore while still producing a call that validates.
ToolEnvelope parseToolEnvelope(
  String text,
  Set<String> validNames, {
  List<FunctionTool> functions = const [],
}) {
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

  if (hasCall) {
    if (kToolCallMarker.allMatches(t).length > 1) notes.add('duplicate-marker');
    if (!t.startsWith(kToolCallMarker)) notes.add('prose-before');

    // Between the first marker and the next one, if the model repeated it.
    final payload =
        t.split(kToolCallMarker)[1].split(kToolCallMarker).first.trim();
    for (final candidate in [payload, extractJson(payload)]) {
      final decoded = _tryDecodeObject(candidate);
      final calls = decoded?['calls'];
      if (calls is List) {
        final read = _callsFrom(calls, validNames, functions);
        if (read != null) return EnvelopeCalls(read, notes);
      }
    }
    final fromPayload =
        detectToolCalls(payload, validNames, functions: functions);
    if (fromPayload != null) return EnvelopeCalls(fromPayload, notes);

    // An explicitly EMPTY calls array is the model choosing this envelope and
    // saying there are none. Detection is right to see no call there, but at
    // this layer the emptiness IS the answer — reading it as unreadable would
    // spend a repair round trip on a perfectly clear reply. Only the
    // documented shape counts: a bare [] elsewhere is data.
    for (final candidate in [payload, extractJson(payload)]) {
      if (_tryDecodeObject(candidate)?['calls'] case final List<dynamic> l
          when l.isEmpty) {
        return EnvelopeCalls(const [], notes);
      }
    }
    notes.add('marker-payload-unreadable');
  } else {
    notes.add('no-marker');
  }

  // No usable marker payload. The model may still have called, just not in the
  // shape it was asked for — read the whole reply as any dialect.
  final dialect = detectToolCalls(text, validNames, functions: functions);
  if (dialect != null) return EnvelopeCalls(dialect, [...notes, 'dialect']);
  return EnvelopeUnreadable([...notes, 'invalid-json']);
}

/// Reads the documented `{"calls": [...]}` payload through the same allow-list
/// and repair the dialect path uses, so the fast path and the fallback can
/// never disagree about what a call is.
List<ToolCall>? _callsFrom(
    List<dynamic> calls, Set<String> validNames, List<FunctionTool> functions) {
  final encoded = jsonEncode(calls);
  return detectToolCalls(encoded, validNames, functions: functions);
}

Map<String, dynamic>? _tryDecodeObject(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}
