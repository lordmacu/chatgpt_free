import 'dart:convert';

import '../events.dart';
import '../models/models.dart';
import 'delta.dart';
import 'pua.dart';
import 'reader.dart';

final RegExp _writingBlock = RegExp(
  r':::writing\{([^}]*)\}\s*(.*?)\s*:::',
  dotAll: true,
);
final RegExp _titleAttr = RegExp(r'title="([^"]*)"');

/// Turns a stream of [SseFrame]s into typed [ChatEvent]s.
///
/// One instance parses one turn; state left behind afterwards
/// ([conversationId], [actualModel], [citations], [limits]) is what the session
/// needs to prepare the next turn.
class TurnParser {
  /// Creates a parser for a turn that asked for [requestedModel].
  TurnParser({required this.requestedModel});

  /// The model the caller asked for, used to detect a silent downgrade.
  final String requestedModel;

  final DeltaApplier _applier = DeltaApplier();

  /// Conversation id learned from the stream, for follow-up turns.
  String conversationId = '';

  /// The model that actually answered.
  String actualModel = '';

  /// Citations collected during the turn.
  List<Citation> citations = const [];

  /// Quota snapshot reported inline, when the backend sent one.
  Limits? limits;

  String _emittedText = '';
  bool _downgradeReported = false;
  final Set<String> _seenWidgets = <String>{};

  /// Parses [frames], emitting events as they become known.
  Stream<ChatEvent> parse(Stream<SseFrame> frames) async* {
    await for (final frame in frames) {
      final dynamic decoded;
      try {
        decoded = jsonDecode(frame.data);
      } on FormatException {
        continue; // a malformed frame must not kill the turn
      }
      if (decoded is! Map<String, dynamic>) continue;

      final type = decoded['type'];
      if (type is String) {
        yield* _handleControl(type, decoded);
        continue;
      }

      _applier.apply(decoded);
      yield* _emitGenuiWidgets();
      yield* _emitTextDelta();
      yield* _emitCitations();
      yield* _emitDowngrade();
    }

    yield* _emitCanvas();
    yield TurnCompleted(
      actualModel: actualModel,
      finishReason: _finishReason(),
      limits: limits,
    );
  }

  Stream<ChatEvent> _handleControl(
      String type, Map<String, dynamic> event) async* {
    switch (type) {
      case 'resume_conversation_token':
        final id = event['conversation_id'];
        if (id is String) conversationId = id;
      case 'conversation_detail_metadata':
        limits = _parseLimits(event);
      case 'url_moderation':
        final url = event['url'];
        if (url is String) yield SearchStarted([url]);
      default:
        return;
    }
  }

  Limits _parseLimits(Map<String, dynamic> event) {
    final remaining = <String, int>{};
    for (final entry in (event['limits_progress'] as List? ?? const [])) {
      if (entry is Map &&
          entry['feature_name'] is String &&
          entry['remaining'] is int) {
        remaining[entry['feature_name'] as String] = entry['remaining'] as int;
      }
    }
    final capped = <String>[
      for (final m in (event['model_limits'] as List? ?? const []))
        if (m is Map && m['model_slug'] is String) m['model_slug'] as String
    ];
    final blocked = <String>[
      for (final b in (event['blocked_features'] as List? ?? const []))
        if (b is Map && b['name'] is String) b['name'] as String
    ];
    return Limits(
      remaining: remaining,
      cappedModels: capped,
      blockedFeatures: blocked,
    );
  }

  String get _rawText {
    final message = _applier.document['message'];
    if (message is! Map) return '';
    // The backend multiplexes every message of the turn (the echoed user
    // prompt, hidden system/developer messages, tool calls, and finally the
    // assistant's reply) through the same "message" slot, each one replacing
    // the last as its channel takes over. Reading parts/0 unconditionally
    // means that for a few frames early in the stream this getter returns
    // the *user's own prompt*, not the reply — and that leaked into the
    // emitted text once already. Only the assistant's own text channel (or a
    // message with no author at all, as in hand-built deltas/tests) is a
    // legitimate source of reply text.
    final author = message['author'];
    final authorRole = author is Map ? author['role'] : null;
    if (authorRole is String && authorRole != 'assistant') return '';
    final content = message['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return '';
    final first = parts.first;
    return first is String ? first : '';
  }

  Stream<ChatEvent> _emitTextDelta() async* {
    // A structured marker can arrive split across two SSE chunks: the
    // opening \uE200/kind/\uE202/ref lands in one delta, the closing
    // \uE201 in the next. Between those two frames stripPuaMarkers cannot
    // recognise the marker yet — it only removes the lone control
    // characters and leaves the kind/ref payload sitting in plain text.
    // Once the marker closes, that whole stretch collapses to nothing, so
    // anything already emitted from it would need to be retracted — which
    // a plain append-only TextDelta stream cannot do. So: never strip or
    // emit past an unterminated marker; wait for it to close first. This
    // keeps the cleaned prefix monotonically growing, which is what the
    // length-diff below assumes.
    final raw = _rawText;
    final safe = raw.substring(0, _safeTextBoundary(raw));
    final clean = stripPuaMarkers(safe);
    if (clean.length <= _emittedText.length) return;
    final delta = clean.substring(_emittedText.length);
    _emittedText = clean;
    if (delta.isNotEmpty) yield TextDelta(delta);
  }

  /// The index in [raw] up to which text is safe to strip and display —
  /// i.e. before any structured marker that has opened (`\uE200`) but not
  /// yet closed (`\uE201`).
  int _safeTextBoundary(String raw) {
    final markers = findPuaMarkers(raw);
    final searchFrom = markers.isEmpty ? 0 : markers.last.end;
    final openStart = raw.indexOf('\u{e200}', searchFrom);
    return openStart == -1 ? raw.length : openStart;
  }

  Stream<ChatEvent> _emitCitations() async* {
    final message = _applier.document['message'];
    if (message is! Map) return;
    final metadata = message['metadata'];
    if (metadata is! Map) return;
    final refs = metadata['content_references'];
    if (refs is! List) return;

    final found = <Citation>[];
    for (final ref in refs) {
      if (ref is! Map) continue;
      for (final item in (ref['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final url = item['url'];
        if (url is! String || url.isEmpty) continue;
        final title = item['title'];
        final attribution = item['attribution'];
        found.add(Citation(
          title: title is String ? title : url,
          url: url,
          attribution: attribution is String ? attribution : null,
        ));
      }
    }
    if (!_citationsEqual(found, citations)) {
      citations = found;
      yield CitationsReceived(List.unmodifiable(found));
    }
  }

  /// Whether [a] and [b] carry the same citations in the same order.
  ///
  /// A count-only comparison misses an existing citation being patched in
  /// place (e.g. its attribution corrected after the fact) — real traffic
  /// does exactly this, it is just masked in some captures by a citation
  /// count change landing in the same patch.
  bool _citationsEqual(List<Citation> a, List<Citation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title ||
          a[i].url != b[i].url ||
          a[i].attribution != b[i].attribution) {
        return false;
      }
    }
    return true;
  }

  Stream<ChatEvent> _emitDowngrade() async* {
    final message = _applier.document['message'];
    if (message is! Map) return;
    // Same reasoning as _rawText: the shared document slot briefly holds
    // the echoed user message (and hidden system messages) before the
    // assistant's own message takes over. Reading model_slug from
    // whichever message happens to occupy the slot means the downgrade
    // decision — and actualModel — could be made from the user's turn
    // metadata instead of the model that actually answered.
    final author = message['author'];
    final authorRole = author is Map ? author['role'] : null;
    if (authorRole is String && authorRole != 'assistant') return;
    final metadata = message['metadata'];
    if (metadata is! Map) return;
    final slug = metadata['model_slug'] ?? metadata['resolved_model_slug'];
    if (slug is! String || slug.isEmpty) return;

    actualModel = slug;
    if (_downgradeReported || requestedModel == 'auto') return;
    if (slug != requestedModel) {
      _downgradeReported = true;
      yield ModelDowngraded(requested: requestedModel, actual: slug);
    }
  }

  Stream<ChatEvent> _emitGenuiWidgets() async* {
    // Widgets ride inline in the text as genui{json} and are
    // stripped from the display text by stripPuaMarkers. Emit each one once.
    for (final marker in findPuaMarkers(_rawText)) {
      if (marker.kind != 'genui') continue;
      if (!_seenWidgets.add(marker.ref)) continue;
      try {
        final decoded = jsonDecode(marker.ref);
        if (decoded is Map<String, dynamic>) {
          yield GenuiWidgetEvent(
            (decoded['name'] ?? 'unknown').toString(),
            Map<String, dynamic>.from(
                decoded['data'] as Map? ?? const <String, dynamic>{}),
          );
        }
      } on FormatException {
        continue; // a widget we cannot parse must not kill the turn
      }
    }
  }

  Stream<ChatEvent> _emitCanvas() async* {
    final match = _writingBlock.firstMatch(_emittedText);
    if (match == null) return;
    final attrs = match.group(1) ?? '';
    yield CanvasDocument(
      markdown: (match.group(2) ?? '').trim(),
      title: _titleAttr.firstMatch(attrs)?.group(1),
    );
  }

  String? _finishReason() {
    final message = _applier.document['message'];
    if (message is! Map) return null;
    final metadata = message['metadata'];
    if (metadata is Map) {
      final details = metadata['finish_details'];
      if (details is Map && details['type'] is String) {
        return details['type'] as String;
      }
    }
    final status = message['status'];
    return status is String ? status : null;
  }
}
