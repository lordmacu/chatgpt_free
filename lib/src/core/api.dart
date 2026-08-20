import 'dart:convert';

import 'errors.dart';
import 'models/models.dart';

/// How much of a malformed response body to keep in a [ProtocolException]
/// message: enough to debug with, short enough that a stray HTML error page
/// from a proxy — or a megabyte of JSON — never ends up in full inside an
/// exception message.
const int _kMaxBodyExcerpt = 300;

String _excerpt(String body) =>
    body.substring(0, body.length.clamp(0, _kMaxBodyExcerpt));

/// Decodes [body] as JSON, or raises [ProtocolException] if it is not valid
/// JSON at all — an empty body, or an HTML error page from a proxy/gateway
/// sitting in front of the backend, are the two real-world cases this guards.
dynamic _decodeJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw ProtocolException('response body is not valid JSON: ${_excerpt(body)}');
  }
}

/// Requires [decoded] to be a JSON object, or raises [ProtocolException].
///
/// A body that parses as JSON but isn't a top-level object — a bare array,
/// string, number, or `null` — is just as unusable to these parsers as
/// invalid JSON: there is no field to read a model list or a translation
/// out of, so it is malformed for this purpose, not a well-formed "empty"
/// response. See parseModels/parseLimits/parseTranslation for how an
/// *absent* field within an actual object is treated differently.
Map<String, dynamic> _requireMap(dynamic decoded, String body) {
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw ProtocolException(
      'expected a JSON object at the top level, got ${decoded.runtimeType}: '
      '${_excerpt(body)}');
}

/// Reads [field] out of [decoded] as a list.
///
/// A field that is absent, or explicitly `null`, is a well-formed "there is
/// nothing here" and yields an empty list — `{}` and `{"$field": []}` mean
/// the same thing to every caller of this function. A field that *is*
/// present with the wrong shape (a string where a list was expected, for
/// instance) is malformed: it means the backend's response shape changed
/// in a way this package does not understand, and raising here — instead of
/// letting an unguarded `as List?` cast throw a raw [TypeError] — is what
/// lets a consumer catch every parse failure as one [ChatGptException].
List<dynamic> _listField(Map<String, dynamic> decoded, String field, String body) {
  final value = decoded[field];
  if (value == null) return const [];
  if (value is List) return value;
  throw ProtocolException(
      'expected "$field" to be a list, got ${value.runtimeType}: ${_excerpt(body)}');
}

/// Parses the `/models` response into [ModelInfo]s.
List<ModelInfo> parseModels(String body) {
  final decoded = _requireMap(_decodeJson(body), body);
  final raw = _listField(decoded, 'models', body);
  return [
    for (final m in raw)
      if (m is Map && m['slug'] is String)
        ModelInfo(
          id: m['slug'] as String,
          title: (m['title'] ?? m['slug']).toString(),
          contextWindow: m['max_tokens'] is int ? m['max_tokens'] as int : null,
          reasoningType: m['reasoning_type']?.toString(),
          enabledTools: [
            for (final t in _listField(
                Map<String, dynamic>.from(m), 'enabled_tools', body))
              t.toString()
          ],
        )
  ];
}

/// Parses a `conversation/init` response into a [Limits] snapshot.
Limits parseLimits(String body) {
  final decoded = _requireMap(_decodeJson(body), body);

  final remaining = <String, int>{};
  for (final e in _listField(decoded, 'limits_progress', body)) {
    if (e is Map && e['feature_name'] is String && e['remaining'] is int) {
      remaining[e['feature_name'] as String] = e['remaining'] as int;
    }
  }
  return Limits(
    remaining: remaining,
    cappedModels: [
      for (final m in _listField(decoded, 'model_limits', body))
        if (m is Map && m['model_slug'] is String) m['model_slug'] as String
    ],
    blockedFeatures: [
      for (final b in _listField(decoded, 'blocked_features', body))
        if (b is Map && b['name'] is String) b['name'] as String
    ],
  );
}

/// Pulls the translated text out of a translate response.
///
/// A well-formed body with none of the known keys (`{}`, or a body that
/// only carries fields this package does not recognise) is not an error —
/// it yields `''`, same as an absent field elsewhere in this file.
String parseTranslation(String body) {
  final decoded = _requireMap(_decodeJson(body), body);
  for (final key in ['translation', 'translated_text', 'text']) {
    final v = decoded[key];
    if (v is String && v.isNotEmpty) return v;
  }
  return '';
}
