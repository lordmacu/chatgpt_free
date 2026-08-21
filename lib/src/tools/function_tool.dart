import 'dart:convert';

import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// One function the caller can execute, declared to the extractor.
///
/// The same shape OpenAI's `tools` array carries, so a schema written for the
/// official API works here unchanged.
class FunctionTool {
  /// Creates a declaration.
  const FunctionTool({
    required this.name,
    this.description = '',
    this.parameters = const {
      'type': 'object',
      'properties': <String, dynamic>{}
    },
  });

  /// The function's name, as it comes back in a [ToolCall].
  final String name;

  /// What it does. The model reads this to decide whether it fits a request,
  /// so it earns its keep — an empty description makes selection worse.
  final String description;

  /// JSON Schema for the arguments.
  final Map<String, dynamic> parameters;

  /// Reads a declaration in OpenAI's `tools` shape.
  ///
  /// Accepts both `{"type":"function","function":{...}}` and a bare function
  /// object, because both are in circulation.
  factory FunctionTool.fromJson(Map<String, dynamic> json) {
    final fn = json['type'] == 'function' && json['function'] is Map
        ? Map<String, dynamic>.from(json['function'] as Map)
        : json;
    return FunctionTool(
      name: '${fn['name'] ?? ''}',
      description: '${fn['description'] ?? ''}',
      parameters: fn['parameters'] is Map
          ? Map<String, dynamic>.from(fn['parameters'] as Map)
          : const {'type': 'object', 'properties': <String, dynamic>{}},
    );
  }

  /// The manifest entry the extractor prompt carries.
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

/// What the extractor is allowed to answer.
sealed class ToolChoice {
  /// Creates a choice.
  const ToolChoice();

  /// Call a function when one fits, otherwise report that none does.
  static const ToolChoice auto = AutoToolChoice();

  /// A call is mandatory — "no function fits" is not an allowed answer.
  static const ToolChoice any = AnyToolChoice();

  /// This exact function and no other.
  const factory ToolChoice.function(String name) = NamedToolChoice;
}

/// [ToolChoice.auto].
final class AutoToolChoice extends ToolChoice {
  /// Creates it.
  const AutoToolChoice();
}

/// [ToolChoice.any].
final class AnyToolChoice extends ToolChoice {
  /// Creates it.
  const AnyToolChoice();
}

/// [ToolChoice.function].
final class NamedToolChoice extends ToolChoice {
  /// Creates it.
  const NamedToolChoice(this.name);

  /// The only function the model may call.
  final String name;
}

/// One function call the model produced.
class ToolCall {
  /// Creates a call. [id] is generated when omitted.
  ToolCall({required this.name, required this.arguments, String? id})
      : id = id ?? 'call_${_uuid.v4().replaceAll('-', '').substring(0, 24)}';

  /// Correlation id, in OpenAI's `call_…` shape.
  final String id;

  /// Which function to run.
  final String name;

  /// The arguments, decoded.
  final Map<String, dynamic> arguments;

  /// The arguments as OpenAI carries them — a JSON *string*, not an object.
  String get argumentsJson => jsonEncode(arguments);

  /// The OpenAI `tool_calls` entry for this call.
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': argumentsJson},
      };

  @override
  String toString() => '$name($argumentsJson)';
}
