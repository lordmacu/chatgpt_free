import 'function_tool.dart';

/// Checks each call's arguments against its function's JSON Schema.
///
/// Returns human-readable errors, empty when everything fits. Recursive:
/// nested objects, arrays of objects and enums are all checked, because the
/// measured structural reliability (42 of 42 schema-valid extractions over
/// three levels of nesting) is only meaningful if the check goes that deep.
///
/// This is a deliberate subset of JSON Schema — `type`, `required`, `enum`,
/// `properties`, `items`, `additionalProperties: false`. It exists to catch a
/// model that misread a schema, not to be a conformant validator. A keyword it
/// does not know is ignored rather than treated as a failure: rejecting a valid
/// call is worse here than passing an unusual one through.
List<String> validateToolCalls(
  List<ToolCall> calls,
  List<FunctionTool> functions,
) {
  final byName = {for (final f in functions) f.name: f};
  final errors = <String>[];

  for (final call in calls) {
    final fn = byName[call.name];
    if (fn == null) {
      errors.add('unknown function "${call.name}"');
      continue;
    }
    errors.addAll(
      _walk(call.arguments, fn.parameters).map((e) => '${fn.name}: $e'),
    );
  }
  return errors;
}

List<String> _walk(Object? value, Map<String, dynamic> schema,
    [String path = '']) {
  final where = path.isEmpty ? '<root>' : path;
  final errors = <String>[];

  final type = schema['type'];
  if (type is String && !_matchesType(value, type)) {
    // A wrong type makes every nested check meaningless, so stop here rather
    // than emit a cascade of errors that all describe the same mistake.
    return ['$where: expected $type'];
  }

  final options = schema['enum'];
  if (options is List && !options.contains(value)) {
    errors.add('$where: $value not in enum');
  }

  if (type == 'object' && value is Map) {
    final properties = schema['properties'] is Map
        ? Map<String, dynamic>.from(schema['properties'] as Map)
        : const <String, dynamic>{};

    for (final name in (schema['required'] as List? ?? const [])) {
      if (!value.containsKey(name)) {
        errors.add('${_join(path, '$name')}: missing required');
      }
    }
    for (final entry in value.entries) {
      final property = properties['${entry.key}'];
      if (property is Map) {
        errors.addAll(_walk(entry.value, Map<String, dynamic>.from(property),
            _join(path, '${entry.key}')));
      } else if (schema['additionalProperties'] == false) {
        errors.add('${_join(path, '${entry.key}')}: not allowed');
      }
    }
  }

  final items = schema['items'];
  if (type == 'array' && value is List && items is Map) {
    for (var i = 0; i < value.length; i++) {
      errors.addAll(
          _walk(value[i], Map<String, dynamic>.from(items), _join(path, '$i')));
    }
  }

  return errors;
}

String _join(String path, String segment) =>
    path.isEmpty ? segment : '$path/$segment';

bool _matchesType(Object? value, String type) => switch (type) {
      'string' => value is String,
      // bool is not an int in Dart the way it is in Python, but JSON round
      // trips can still land a bool where a number belongs.
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      'array' => value is List,
      'object' => value is Map,
      'null' => value == null,
      _ => true,
    };
