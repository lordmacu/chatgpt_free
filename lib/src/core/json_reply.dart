import 'dart:convert';

import 'errors.dart';

/// Pulls the JSON out of a reply that asked for JSON.
///
/// A model told to answer in JSON usually still wraps it in a Markdown code
/// fence, and sometimes adds a sentence before or after it. `jsonDecode` on the
/// raw reply therefore fails on perfectly good answers. This strips the fence
/// and, failing that, takes the outermost `{…}` or `[…]` that parses.
///
/// Ported from the Python client's `_extract_json`
/// (chatgpt-proxy/chatgpt_client.py:64-89), which exists for the same reason.
///
/// Returns the reply unchanged when nothing JSON-shaped is found — the caller
/// decides whether that is an error.
String extractJson(String reply) {
  var text = reply.trim();

  if (text.startsWith('```')) {
    final lines = text.split('\n');
    lines.removeAt(0); // opening fence, with or without a language tag
    if (lines.isNotEmpty && lines.last.trimLeft().startsWith('```')) {
      lines.removeLast();
    }
    text = lines.join('\n').trim();
  }

  for (final pair in const [('{', '}'), ('[', ']')]) {
    final start = text.indexOf(pair.$1);
    final end = text.lastIndexOf(pair.$2);
    if (start != -1 && end > start) {
      final candidate = text.substring(start, end + 1);
      try {
        jsonDecode(candidate);
        return candidate;
      } on FormatException {
        // Not this shape; try the next one.
      }
    }
  }
  return text;
}

/// Decodes a JSON reply, raising [ProtocolException] when it is not JSON.
///
/// Use this instead of `jsonDecode(reply)` — see [extractJson] for why the raw
/// reply so often fails to parse even when the model did what it was told.
Object? decodeJsonReply(String reply) {
  final candidate = extractJson(reply);
  try {
    return jsonDecode(candidate);
  } on FormatException catch (e) {
    throw ProtocolException(
      'the reply was not JSON (${e.message}): '
      '${candidate.substring(0, candidate.length.clamp(0, 200))}',
    );
  }
}
