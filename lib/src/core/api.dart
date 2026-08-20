import 'dart:convert';

import 'models/models.dart';

/// Parses the `/models` response into [ModelInfo]s.
List<ModelInfo> parseModels(String body) {
  final decoded = jsonDecode(body);
  final raw = decoded is Map ? (decoded['models'] as List? ?? const []) : const [];
  return [
    for (final m in raw)
      if (m is Map && m['slug'] is String)
        ModelInfo(
          id: m['slug'] as String,
          title: (m['title'] ?? m['slug']).toString(),
          contextWindow: m['max_tokens'] is int ? m['max_tokens'] as int : null,
          reasoningType: m['reasoning_type']?.toString(),
          enabledTools: [
            for (final t in (m['enabled_tools'] as List? ?? const []))
              t.toString()
          ],
        )
  ];
}

/// Parses a `conversation/init` response into a [Limits] snapshot.
Limits parseLimits(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return const Limits();

  final remaining = <String, int>{};
  for (final e in (decoded['limits_progress'] as List? ?? const [])) {
    if (e is Map && e['feature_name'] is String && e['remaining'] is int) {
      remaining[e['feature_name'] as String] = e['remaining'] as int;
    }
  }
  return Limits(
    remaining: remaining,
    cappedModels: [
      for (final m in (decoded['model_limits'] as List? ?? const []))
        if (m is Map && m['model_slug'] is String) m['model_slug'] as String
    ],
    blockedFeatures: [
      for (final b in (decoded['blocked_features'] as List? ?? const []))
        if (b is Map && b['name'] is String) b['name'] as String
    ],
  );
}

/// Pulls the translated text out of a translate response.
String parseTranslation(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map) {
    for (final key in ['translation', 'translated_text', 'text']) {
      final v = decoded[key];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return '';
}
