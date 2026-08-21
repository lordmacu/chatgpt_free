import 'dart:convert';

import 'function_tool.dart';
import 'tolerant_json.dart';

/// Repairs argument types against each function's declared schema.
///
/// A prompted model returns scalars as strings far more often than a native
/// tool-caller does — `"5"` where the schema says integer. Every coercion here
/// is lossless or skipped: a value that does not convert CLEANLY to the
/// declared type travels exactly as the model sent it, and parameters the
/// schema does not declare are never touched.
///
/// This is what turns a type mismatch from a repair round trip — one more
/// message off an anonymous hourly allowance — into a first-pass parse.
List<ToolCall>? applySchemas(
    List<ToolCall>? calls, List<FunctionTool> functions) {
  if (calls == null || calls.isEmpty || functions.isEmpty) return calls;

  final byName = {for (final f in functions) f.name: f.parameters};
  return [
    for (final call in calls)
      switch (byName[call.name]?['properties']) {
        final Map<dynamic, dynamic> props => ToolCall(
            id: call.id,
            name: call.name,
            arguments: {
              for (final e in call.arguments.entries)
                e.key: coerceValue(e.value, props[e.key]),
            },
          ),
        _ => call,
      },
  ];
}

/// Coercion reads numbers by JSON's own grammar, not the host language's:
/// `int.parse` accepts forms JSON does not, and accepting them would not be a
/// lossless re-reading of what the model actually wrote.
final RegExp _jsonInt = RegExp(r'^[+-]?[0-9]+$');
final RegExp _jsonNumber =
    RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$');

/// Bounds recursion through nested structures. Schemas arrive as parsed JSON
/// (acyclic by construction), so this is belt: a depth past it stops repairing,
/// never fails.
const int _maxDepth = 8;

/// Whether [value] already inhabits JSON-Schema type [kind].
///
/// A whole double (5.0) is deliberately NOT accepted as `integer`, even though
/// JSON Schema would validate it: rejecting it here routes it through the
/// coercion step, which folds it to the canonical int that strict consumers
/// expect. `bool` is not a number, which is the line JSON Schema draws too —
/// folding true into 1 would rewrite a flag the model may have meant literally.
bool _satisfies(Object? value, String kind) => switch (kind) {
      'string' => value is String,
      'boolean' => value is bool,
      'integer' => value is int,
      'number' => value is num && value is! bool,
      'array' => value is List,
      'object' => value is Map,
      'null' => value == null,
      _ => false,
    };

/// One lossless conversion attempt toward [kind]; the input on failure.
Object? _coerceScalar(Object? value, String kind, List<String> kinds) {
  switch (kind) {
    case 'integer':
      if (value is String && _jsonInt.hasMatch(value.trim())) {
        return int.tryParse(value.trim()) ?? value;
      }
      if (value is double && value.isFinite && value == value.roundToDouble()) {
        return value.toInt();
      }
    case 'number':
      if (value is String && _jsonNumber.hasMatch(value.trim())) {
        return double.tryParse(value.trim()) ?? value;
      }
    case 'boolean':
      if (value is String) {
        final t = value.trim().toLowerCase();
        if (t == 'true' || t == 'false') return t == 'true';
      }
    case 'string':
      // bool is excluded: encoding true as "true" silently rewrites a flag the
      // model may have meant literally.
      if (value is num && value is! bool) return jsonEncode(value);
    case 'array':
      if (value is String) {
        final parsed = loadsTolerant(value.trim());
        if (parsed is List) return parsed;
      }
    case 'object':
      if (value is String) {
        final parsed = loadsTolerant(value.trim());
        if (parsed is Map) return parsed;
      }
    case 'null':
      // Only when the union has no "string" member: with one, the literal text
      // "null" is at least as plausibly the string as the null.
      if (value is String &&
          value.trim().toLowerCase() == 'null' &&
          !kinds.contains('string')) {
        return null;
      }
  }
  return value;
}

/// Repairs one value against its schema: losslessly, or not at all.
///
/// In order:
///
/// 1. Enum repair: a string differing from exactly ONE enum member only by
///    case or padding becomes that member. Two members colliding
///    case-insensitively make a third spelling ambiguous — untouched.
/// 2. Identity: a value already satisfying ANY declared type (`type` may be a
///    union list) is never converted — `"5"` under `["integer","string"]` IS
///    the string. The one exception is a whole double under `integer`, folded
///    to the canonical int.
/// 3. Otherwise the declared types are tried in order and the first clean
///    conversion wins; no clean conversion, no change.
/// 4. Structure recursion: maps repair their declared properties, lists repair
///    every element against `items` — bounded by depth.
///
/// Idempotent: every repaired value satisfies its type, and step 2 makes
/// satisfying values fixed points.
Object? coerceValue(Object? value, Object? schema, [int depth = 0]) {
  if (schema is! Map || depth > _maxDepth) return value;

  var out = value;

  final options = schema['enum'];
  if (options is List && out is String && !options.contains(out)) {
    final matches = options
        .whereType<String>()
        .where((e) => e.toLowerCase() == out.toString().trim().toLowerCase())
        .toList();
    if (matches.length == 1) out = matches.single;
  }

  final declared = schema['type'];
  final kinds = switch (declared) {
    final String s => [s],
    final List<dynamic> l => l.whereType<String>().toList(),
    _ => const <String>[],
  };

  if (!kinds.any((k) => _satisfies(out, k))) {
    for (final kind in kinds) {
      final converted = _coerceScalar(out, kind, kinds);
      if (!identical(converted, out)) {
        out = converted;
        break;
      }
    }
  } else if (kinds.contains('integer') &&
      out is double &&
      out.isFinite &&
      out == out.roundToDouble()) {
    out = out.toInt();
  }

  if (out is Map) {
    final props = schema['properties'];
    if (props is Map) {
      out = {
        for (final e in out.entries)
          e.key: coerceValue(e.value, props[e.key], depth + 1),
      };
    }
  } else if (out is List) {
    final items = schema['items'];
    if (items is Map) {
      out = [for (final v in out) coerceValue(v, items, depth + 1)];
    }
  }
  return out;
}
