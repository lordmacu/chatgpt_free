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
  bool _searchStartedReported = false;
  final Set<String> _seenWidgets = <String>{};
  bool _replyCompleted = false;

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
      yield* _emitSearchStarted();
    }

    yield* _emitCanvas();
    // Guarantee it: a stream that ends without message_stream_complete must
    // still let a UI stop its indicator.
    if (!_replyCompleted) {
      _replyCompleted = true;
      yield const ReplyCompleted();
    }
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
      // Deliberately no case here for 'url_moderation': real frames (see
      // test/fixtures/web_search.sse lines 70/78) carry the URL nested at
      // `url_moderation_result.full_url`, never at a top-level `url` key —
      // reading `event['url']` here was always null, so this event type
      // never fired against real traffic (Final review, Blocker 2). It also
      // never carries search *queries*, only URLs already found, so it is
      // not the right source for [SearchStarted] even once read correctly.
      // See [_emitSearchStarted] for where the real queries live.
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

  // Invariant this method exists to guarantee: a consumer that folds every
  // TextDelta — starting from '', replacing its running text with .text
  // when .isReset is true and appending it otherwise — always ends the
  // turn holding exactly the text the backend ended it with. That holds
  // for two independent reasons:
  //
  // 1. A structured marker can arrive split across two SSE chunks: the
  //    opening \uE200/kind/\uE202/ref lands in one delta, the closing
  //    \uE201 in the next. Between those two frames stripPuaMarkers cannot
  //    recognise the marker yet — it only removes the lone control
  //    characters and leaves the kind/ref payload sitting in plain text.
  //    _safeTextBoundary withholds that unsettled tail so `clean` never
  //    reflects a marker that might still close differently.
  // 2. DeltaApplier's `replace` and `truncate` are not scoped away from
  //    the text channel — the backend can edit already-streamed text at
  //    any path, including this one. No withholding strategy can predict
  //    that in advance (it is not signalled the way an open marker is), so
  //    when it happens `clean` can be shorter than, or simply diverge
  //    from, what was already emitted. A purely additive delta cannot
  //    retract the stale tail in that case, so this is where isReset:true
  //    is used: the consumer is told to discard what it has and adopt
  //    `clean` wholesale, rather than told to (impossibly) append to it.
  Stream<ChatEvent> _emitTextDelta() async* {
    final raw = _rawText;
    final safe = raw.substring(0, _safeTextBoundary(raw));
    final clean = stripPuaMarkers(safe);
    if (clean == _emittedText) return;
    if (clean.startsWith(_emittedText)) {
      final delta = clean.substring(_emittedText.length);
      _emittedText = clean;
      if (delta.isNotEmpty) yield TextDelta(delta);
    } else {
      _emittedText = clean;
      yield TextDelta(clean, isReset: true);
    }
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

  // The backend announces a web search on the tool message it uses to run
  // it (author.role == 'tool', author.name == 'web.run'), as
  // `/message/metadata/search_model_queries/queries` — see
  // test/fixtures/web_search.sse line 38. That tool message occupies the
  // shared document slot only briefly: later deltas in the same turn
  // replace `/message` wholesale with the next message in the multiplex
  // (the assistant's own reply, citation-carrying messages, and so on), so
  // by the time a consumer might think to look, `search_model_queries` is
  // already gone from `_applier.document`. This must therefore be checked
  // on every delta, right after `_applier.apply`, not lazily from a getter
  // the way `_emitCitations`/`_emitDowngrade` can afford to.
  Stream<ChatEvent> _emitSearchStarted() async* {
    if (_searchStartedReported) return;
    final message = _applier.document['message'];
    if (message is! Map) return;
    final metadata = message['metadata'];
    if (metadata is! Map) return;
    final searchModelQueries = metadata['search_model_queries'];
    if (searchModelQueries is! Map) return;
    final queries = searchModelQueries['queries'];
    if (queries is! List || queries.isEmpty) return;

    final strings = [
      for (final q in queries)
        if (q is String) q
    ];
    if (strings.isEmpty) return;

    _searchStartedReported = true;
    yield SearchStarted(strings);
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
