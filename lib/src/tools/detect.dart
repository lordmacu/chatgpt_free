/// Reading a tool call back out of a model's prose.
///
/// Ported from llm-libre's `tool_emulator`, which solves the harder half of the
/// same problem: it reads calls out of an ordinary conversation turn, from any
/// provider, in whatever dialect each fine-tune emits. Here the model was asked
/// for one exact format in a dedicated request, so the documented envelope is
/// the fast path — but a model answering in a neighbouring dialect used to cost
/// a repair round trip, and a repair round trip is one more message off an
/// anonymous hourly allowance.
///
/// **The central risk is a false positive.** Turning a genuine text answer into
/// a tool call is worse than missing one: the app runs a function the user
/// never asked for. Every heuristic here is therefore gated on [validNames] —
/// the functions declared in THIS request, narrowed by its own [ToolChoice].
/// A JSON object naming anything else stays text.
library;

import 'function_tool.dart';
import 'schema_coerce.dart';
import 'tolerant_json.dart';

// ---------------------------------------------------------------------------
// What has to come off before any brace scanning
// ---------------------------------------------------------------------------

final RegExp _thinkBlock = RegExp(
  r'<(think|thinking|reasoning)>.*?</\1>',
  dotAll: true,
  caseSensitive: false,
);

/// A scratchpad cut off before its closing tag — a truncated stream, a model
/// that ran out of tokens mid-thought — is reasoning to the end of the text.
/// Left in place, a draft call inside it is indistinguishable from an answer.
final RegExp _thinkUnclosed = RegExp(
  r'<(think|thinking|reasoning)>(?:(?!</\1>)[\s\S])*$',
  caseSensitive: false,
);

/// Mistral fine-tunes prefix their calls with a literal control token; what
/// follows is the ordinary array the rest of the parser already reads.
/// Anchored to the start on purpose: elsewhere the same bytes are far more
/// likely to be argument DATA than a marker.
final RegExp _toolCallsMarker = RegExp(r'^\s*\[/?TOOL_CALLS\]\s*');

/// Some open-weights models wrap calls in an XML-ish tag instead of bare JSON.
final RegExp _toolCallTag = RegExp(
  r'<tool_call>\s*([\s\S]*?)\s*</tool_call>',
  caseSensitive: false,
);

/// Only fence labels that MARK a call count as deliberate. A ```python fence
/// stays a bare-scan region — code examples full of dict literals must keep
/// having to earn conversion through the prose heuristics.
final RegExp _codeFence =
    RegExp(r'```(?:json|JSON|tool_call|tool_code)?\s*([\s\S]*?)\s*```');

/// An embedded JSON object surrounded by much more prose is far more likely to
/// be the model TALKING ABOUT a call than making one.
const double _embeddedMinShare = 0.5;

/// Keys under which vendors put the arguments; the first present wins.
const List<String> _argumentKeys = ['arguments', 'input', 'parameters', 'args'];

/// Name-key spellings with the argument keys that accompany each. The first
/// name-ish key PRESENT decides the shape; if its value fails the allow-list
/// the object is data, and no further digging is allowed — an object that
/// names one thing and wraps another did not clearly call anything.
const List<(String, List<String>)> _nameKeyTable = [
  ('name', _argumentKeys),
  ('action', ['action_input', ..._argumentKeys]),
  ('tool', ['tool_input', ..._argumentKeys]),
];

/// Envelope keys some models wrap a call in.
const List<String> _callWrapperKeys = [
  'function_call',
  'tool_call',
  'tool_use',
  'function',
];

/// Namespace prefixes OpenAI-tuned models leak from their training format
/// (`functions.get_weather`). Stripping one never invents a match: the tail
/// still has to clear the same allow-list.
const List<String> _namespacePrefixes = ['functions', 'tools'];

/// The bare scan's work bound: each unclosed opener buys one walk to the end,
/// so this caps the scan at O(k·n) on any input.
const int _maxUnclosedScans = 8;

// ---------------------------------------------------------------------------
// The allow-list: ToolChoice as a contract, not a hint
// ---------------------------------------------------------------------------

/// The names detection may produce once [choice] has had its say.
///
/// A choice does not only demand calls, it NARROWS them: a caller that pinned
/// one function has not authorised any other. Gating detection on this instead
/// of the raw declared list is what turns [ToolChoice] from a hint the prompt
/// makes into a contract the parser keeps — without it, a model that ignores a
/// pinned choice and calls a different *declared* function produces a call
/// that validates cleanly and runs the wrong thing.
Set<String> allowedNames(List<FunctionTool> functions, ToolChoice choice) {
  final names = {for (final f in functions) f.name};
  return switch (choice) {
    NamedToolChoice(:final name) => names.intersection({name}),
    _ => names,
  };
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// Reads model output as tool calls, accepting only [validNames].
///
/// Returns a non-empty list, or null. Never throws: every input is either a
/// call list or null. [functions], when given, repairs argument types against
/// each declared schema — losslessly or not at all.
List<ToolCall>? detectToolCalls(
  String text,
  Set<String> validNames, {
  List<FunctionTool> functions = const [],
}) {
  if (validNames.isEmpty || text.isEmpty) return null;

  // Reasoning scratchpads first: their braces would otherwise anchor the
  // balanced scan on content that is not the answer.
  var cleaned = text.replaceAll(_thinkBlock, '');
  cleaned = cleaned.replaceAll(_thinkUnclosed, '');
  cleaned = cleaned.replaceFirst(_toolCallsMarker, '').trim();
  if (cleaned.isEmpty) return null;

  // Every <tool_call> tag is a deliberate, marked invocation, so ALL of them
  // together are the answer: models trained on that format emit one tag per
  // parallel call. A tag whose payload fails the allow-list is dropped, not
  // fatal — the calls that did qualify are still the calls the model made.
  final tagged = <ToolCall>[];
  for (final m in _toolCallTag.allMatches(cleaned)) {
    final calls = _parseCandidate(m.group(1)!.trim(), validNames);
    if (calls != null) tagged.addAll(calls);
  }
  if (tagged.isNotEmpty) return applySchemas(tagged, functions);

  // A response that is EXACTLY a JSON array is authoritative: the model chose
  // that structure deliberately, so the all-or-nothing rule decides it
  // outright rather than letting the single-object fallback resurrect one call
  // from what is much more likely a list of data.
  if (cleaned.startsWith('[') && loadsTolerant(cleaned) is List) {
    return applySchemas(_parseCandidate(cleaned, validNames), functions);
  }

  // Among several parseable candidates the LAST one wins. A model that
  // illustrates the format before committing ("here is how I would call it:
  // ``` … ``` — now the real call: {…}") puts the demo first and the real call
  // last, so taking the first match hands back the example's arguments.
  (int, List<ToolCall>)? best;
  for (final candidate in _jsonCandidates(cleaned)) {
    if (candidate.text.isEmpty || !candidate.qualifies) continue;
    final calls = _parseCandidate(candidate.text, validNames);
    if (calls != null && (best == null || candidate.position >= best.$1)) {
      best = (candidate.position, calls);
    }
  }
  return best == null ? null : applySchemas(best.$2, functions);
}

class _Candidate {
  const _Candidate(this.position, this.text, this.qualifies);
  final int position;
  final String text;

  /// The prose-vs-invocation verdict. Candidates carrying a deliberate marker
  /// always qualify; a bare object loose in a paragraph has to earn it.
  final bool qualifies;
}

/// Replaces every match with spaces, preserving offsets, so the bare scan skips
/// regions already claimed by an explicit marker.
String _blankOut(String text, RegExp pattern) =>
    text.replaceAllMapped(pattern, (m) => ' ' * m.group(0)!.length);

List<_Candidate> _jsonCandidates(String text) {
  final found = <_Candidate>[];
  for (final m in _toolCallTag.allMatches(text)) {
    found.add(_Candidate(m.start, m.group(1)!.trim(), true));
  }
  for (final m in _codeFence.allMatches(text)) {
    found.add(_Candidate(m.start, m.group(1)!.trim(), true));
  }

  // Scan over a copy with fences and tags blanked out, so an illustrative
  // example inside a fence is not re-discovered as if it were loose text.
  final residual = _blankOut(_blankOut(text, _toolCallTag), _codeFence);
  final spans = <(int, int, String)>[];

  // Every unclosed opener costs one walk to the end before the scan can step
  // past it. Unbudgeted, a storm of bare openers makes the scan quadratic in
  // the response size. The budget keeps total work linear and gives up in the
  // SAFE direction: a missed call, never an invented one.
  var budget = _maxUnclosedScans;
  for (final pair in [('[', ']'), ('{', '}')]) {
    var pos = 0;
    while (budget > 0) {
      final hit = _balancedSpan(residual, pair.$1, pair.$2, pos);
      if (hit == null) break;
      final (span, start) = hit;
      if (span == null) {
        budget--;
        pos = start + 1;
        continue;
      }
      spans.add((start, start + span.length, span));
      pos = start + span.length;
    }
  }
  spans.sort((a, b) => a.$1.compareTo(b.$1));

  for (final (start, _, span) in spans) {
    found.add(
        _Candidate(start, span, _looksLikeAnInvocation(span, residual, start)));
  }

  // Runs of bare spans separated by nothing but whitespace are also offered
  // joined into one synthetic array — the JSONL habit of models that emit one
  // object per line instead of the documented array.
  for (final run in _whitespaceRuns(spans, residual)) {
    if (run.length < 2) continue;
    final firstStart = run.first.$1;
    final lastEnd = run.last.$2;
    final joined = '[${run.map((s) => s.$3).join(', ')}]';
    final qualifies = firstStart <= 0 ||
        residual.substring(lastEnd).trim().isEmpty ||
        (lastEnd - firstStart) / residual.length >= _embeddedMinShare;
    found.add(_Candidate(run.last.$1, joined, qualifies));
  }
  return found;
}

/// Groups sorted spans into runs separated by whitespace only.
///
/// Overlapping spans (an object already inside a scanned array) and spans with
/// prose between them each start a new run: only true side-by-side emission
/// reads as one batch.
List<List<(int, int, String)>> _whitespaceRuns(
    List<(int, int, String)> spans, String text) {
  final runs = <List<(int, int, String)>>[];
  for (final span in spans) {
    if (runs.isNotEmpty) {
      final prevEnd = runs.last.last.$2;
      if (span.$1 >= prevEnd &&
          text.substring(prevEnd, span.$1).trim().isEmpty) {
        runs.last.add(span);
        continue;
      }
    }
    runs.add([span]);
  }
  return runs;
}

/// Scans for the next balanced span from [begin].
///
/// Returns `(span, start)`; span is null when an opener was found but never
/// closed (the caller may resume past it), and the whole result is null when no
/// opener remains.
///
/// Brace-counting rather than a regex, and string-aware for BOTH quote styles:
/// a brace inside a JSON string value must not close the object, the same brace
/// inside a Python-literal string must not either, and a backslash-escaped
/// quote must not end the string.
(String?, int)? _balancedSpan(
    String text, String opener, String closer, int begin) {
  final start = text.indexOf(opener, begin);
  if (start == -1) return null;

  var depth = 0;
  String? quote;
  var escaped = false;

  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch == r'\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (ch == quote) quote = null;
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == opener) {
      depth++;
    } else if (ch == closer) {
      depth--;
      if (depth == 0) return (text.substring(start, i + 1), start);
    }
  }
  return (null, start);
}

/// Whether a bare JSON object is a call or just prose.
///
/// A model that is actually calling opens with the JSON, or works up to it and
/// ends there. A model quoting the tool's own schema to ask a clarifying
/// question ("its schema is {…}, but which city?") leaves a small object
/// stranded mid-sentence with the question after it, and converting that
/// destroys the question and issues a call the model never intended.
bool _looksLikeAnInvocation(String span, String whole, int position) {
  if (position <= 0) return true;
  if (whole.isEmpty) return false;
  if (whole.substring(position + span.length).trim().isEmpty) return true;
  return span.length / whole.length >= _embeddedMinShare;
}

List<ToolCall>? _parseCandidate(String text, Set<String> validNames) {
  final decoded = loadsTolerant(text);
  return decoded == null ? null : _callsFromObject(decoded, validNames);
}

List<ToolCall>? _callsFromObject(Object? obj, Set<String> validNames) {
  if (obj is List) {
    final calls = [
      for (final item in obj)
        if (_extractCall(item, validNames) case final ToolCall c) c,
    ];
    // Every element must be a valid call. A list where only some entries
    // qualify is far more likely to be data the model returned than a batch of
    // calls, and converting it would invent calls it never made.
    return calls.isNotEmpty && calls.length == obj.length ? calls : null;
  }

  if (obj is Map) {
    final call = _extractCall(obj, validNames);
    if (call != null) return [call];
    // {"tool_calls": [...]} mirrors the RESPONSE shape these models were
    // fine-tuned on. Same all-or-nothing rule as any other batch.
    final batch = obj['tool_calls'];
    if (batch is List && batch.isNotEmpty) {
      return _callsFromObject(batch, validNames);
    }
  }
  return null;
}

/// Normalises one object into a call, across known vendor shapes:
/// `name`/`arguments` (documented), `input` (Anthropic), `parameters`/`args`
/// (open weights), `action`/`action_input` (ReAct), `tool`/`tool_input`,
/// and the `function_call`/`tool_call`/`tool_use`/`function` wrappers.
ToolCall? _extractCall(Object? obj, Set<String> validNames) {
  if (obj is! Map) return null;

  for (final (nameKey, argumentKeys) in _nameKeyTable) {
    final name = obj[nameKey];
    if (name is String && name.isNotEmpty) {
      for (final key in argumentKeys) {
        if (obj.containsKey(key)) {
          return _normalise(name, obj[key], validNames);
        }
      }
      // A name with no arguments key at all is a legitimate zero-argument call.
      return _normalise(name, const <String, dynamic>{}, validNames);
    }
  }

  for (final key in _callWrapperKeys) {
    final inner = obj[key];
    if (inner is Map) {
      final call = _extractCall(inner, validNames);
      if (call != null) return call;
    }
  }
  return null;
}

/// Maps an emitted name onto the declared one it clearly means, or null.
///
/// Exact match first. Then the same name with a leaked vendor namespace
/// stripped, then a case-insensitive match — accepted only when it is UNIQUE:
/// if two declared names differ only by case, a third spelling names neither
/// and stays text. Every path still ends inside [validNames]; nothing here can
/// invent a function nobody declared.
String? _resolveName(String name, Set<String> validNames) {
  final candidates = [name];
  final dot = name.indexOf('.');
  if (dot > 0) {
    final head = name.substring(0, dot);
    final tail = name.substring(dot + 1);
    if (_namespacePrefixes.contains(head) && tail.isNotEmpty) {
      candidates.add(tail);
    }
  }
  for (final candidate in candidates) {
    if (validNames.contains(candidate)) return candidate;
  }
  for (final candidate in candidates) {
    final matches = validNames
        .where((n) => n.toLowerCase() == candidate.toLowerCase())
        .toList();
    if (matches.length == 1) return matches.single;
  }
  return null;
}

ToolCall? _normalise(String name, Object? arguments, Set<String> validNames) {
  final resolved = _resolveName(name, validNames);
  if (resolved == null) return null;

  var decoded = arguments;
  if (decoded is String) {
    final text = decoded.trim();
    // Malformed argument JSON degrades to {}: the name is valid and the model
    // clearly meant to call, so the call is kept with empty arguments rather
    // than dropped — the app gets a call it can reject, instead of prose it
    // will misread as an answer.
    decoded = text.isEmpty ? null : loadsTolerant(text);
  }

  return ToolCall(
    name: resolved,
    arguments: decoded is Map
        ? {for (final e in decoded.entries) '${e.key}': e.value}
        : <String, dynamic>{},
  );
}
