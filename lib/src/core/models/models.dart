/// A web source the assistant cited.
class Citation {
  /// Creates a citation.
  const Citation({required this.title, required this.url, this.attribution});

  /// Page title.
  final String title;

  /// Source URL.
  final String url;

  /// Publisher, when the backend supplied one.
  final String? attribution;
}

/// A model as reported by the backend, with its real capabilities.
class ModelInfo {
  /// Creates a model description.
  const ModelInfo({
    required this.id,
    required this.title,
    this.contextWindow,
    this.reasoningType,
    this.enabledTools = const [],
  });

  /// Model slug.
  final String id;

  /// Human-readable name.
  final String title;

  /// Token ceiling for this model. There is no per-request token parameter.
  final int? contextWindow;

  /// `auto`, `reasoning` or `none`.
  final String? reasoningType;

  /// Server-side tools this model may use.
  final List<String> enabledTools;
}

/// Quota state, as reported inline on every turn.
class Limits {
  /// Creates a limits snapshot.
  const Limits({
    this.remaining = const {},
    this.cappedModels = const [],
    this.blockedFeatures = const [],
  });

  /// Remaining count per feature name, e.g. `file_upload`.
  final Map<String, int> remaining;

  /// Models currently capped — answers fall back to a smaller model.
  final List<String> cappedModels;

  /// Features blocked outright, e.g. `image_gen` when anonymous.
  final List<String> blockedFeatures;
}

/// A Canvas document extracted from a `:::writing` block.
class CanvasDoc {
  /// Creates a canvas document.
  const CanvasDoc({required this.markdown, this.title});

  /// Document body in Markdown.
  final String markdown;

  /// Document title, when the block declared one.
  final String? title;
}

/// One message in a conversation.
class ChatMessage {
  /// Creates a message.
  const ChatMessage({
    required this.role,
    required this.text,
    this.citations = const [],
    this.isStreaming = false,
  });

  /// `user` or `assistant`.
  final String role;

  /// Display text, PUA markers already stripped.
  final String text;

  /// Sources cited in this message.
  final List<Citation> citations;

  /// True while the assistant is still writing this message.
  final bool isStreaming;

  /// Returns a copy with the given fields replaced.
  ChatMessage copyWith({
    String? text,
    List<Citation>? citations,
    bool? isStreaming,
  }) =>
      ChatMessage(
        role: role,
        text: text ?? this.text,
        citations: citations ?? this.citations,
        isStreaming: isStreaming ?? this.isStreaming,
      );
}

/// A conversation as the backend has it, fetched by id.
///
/// Anonymous conversations are NOT listable — `/conversations` answers 200
/// with an empty page — but a conversation can be fetched by id from the very
/// device that created it. Another device gets 404 "Log in to view this
/// conversation". That is why [ChatGptStore] persists the device id alongside
/// the conversation id: without the former, the latter is unreadable.
class ConversationDetail {
  /// Creates a conversation detail.
  const ConversationDetail({
    required this.id,
    required this.messages,
    this.title,
  });

  /// Server-side conversation id.
  final String id;

  /// Every turn, oldest first.
  final List<ChatMessage> messages;

  /// The title the backend generated for it.
  final String? title;
}
