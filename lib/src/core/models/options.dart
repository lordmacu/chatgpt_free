import '../constants.dart';
import '../errors.dart';

/// How long a reasoning model deliberates. These three are the only values the
/// backend accepts; anything else is HTTP 422.
enum ThinkingEffort {
  /// Default effort.
  standard,

  /// More deliberation.
  extended,

  /// Most deliberation.
  max;

  /// The string sent on the wire.
  String get wire => name;
}

/// Upstream scheduling class. Only these two are accepted.
enum ServiceTier {
  /// Default tier.
  standard,

  /// Priority scheduling.
  priority;

  /// The string sent on the wire.
  String get wire => name;
}

/// A plain-text file attached to a turn. Binary files are not supported by the
/// anonymous flow; extract text in your app first.
class TextAttachment {
  /// Creates an attachment.
  const TextAttachment({required this.name, required this.content});

  /// File name, shown to the model for context.
  final String name;

  /// The file's text content.
  final String content;
}

/// Per-turn options.
class SendOptions {
  /// Creates options for one turn.
  const SendOptions({
    this.model = 'auto',
    this.webSearch,
    this.tools,
    this.canvas,
    this.jsonMode = false,
    this.thinkingEffort,
    this.serviceTier,
  });

  /// Model slug, or `auto` to let the server pick.
  final String model;

  /// Force web search on or off; null lets the model decide.
  final bool? webSearch;

  /// Enable the backend's advanced tools.
  final bool? tools;

  /// Enable Canvas document mode.
  final bool? canvas;

  /// Ask for a JSON-only reply.
  final bool jsonMode;

  /// Reasoning effort, when the model supports it.
  final ThinkingEffort? thinkingEffort;

  /// Upstream scheduling class.
  final ServiceTier? serviceTier;

  /// Throws [InvalidRequestException] if the backend would reject these.
  ///
  /// Validating here matters: an anonymous 422 still costs a message from the
  /// hourly quota.
  void validate() {
    if (model.trim().isEmpty) {
      throw const InvalidRequestException('model must not be empty',
          field: 'model');
    }
    final effort = thinkingEffort?.wire;
    if (effort != null && !kThinkingEfforts.contains(effort)) {
      throw InvalidRequestException('unsupported thinking effort $effort',
          field: 'thinking_effort');
    }
    final tier = serviceTier?.wire;
    if (tier != null && !kServiceTiers.contains(tier)) {
      throw InvalidRequestException('unsupported service tier $tier',
          field: 'service_tier');
    }
  }
}
