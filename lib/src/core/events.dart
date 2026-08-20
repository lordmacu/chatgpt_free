import 'models/models.dart';

/// Everything that can happen during one turn.
sealed class ChatEvent {
  /// Creates an event.
  const ChatEvent();
}

/// A chunk of assistant text, already stripped of PUA markers.
final class TextDelta extends ChatEvent {
  /// Creates a text delta.
  const TextDelta(this.text);

  /// The new text to append.
  final String text;
}

/// The backend ran web searches for this turn.
final class SearchStarted extends ChatEvent {
  /// Creates a search event.
  const SearchStarted(this.queries);

  /// The queries it issued.
  final List<String> queries;
}

/// Sources cited so far in this turn.
final class CitationsReceived extends ChatEvent {
  /// Creates a citations event.
  const CitationsReceived(this.citations);

  /// The citations.
  final List<Citation> citations;
}

/// A generative-UI widget the backend emitted.
final class GenuiWidgetEvent extends ChatEvent {
  /// Creates a widget event.
  const GenuiWidgetEvent(this.name, this.data);

  /// Widget name.
  final String name;

  /// Raw widget payload — deliberately untyped, the schema is not ours.
  final Map<String, dynamic> data;
}

/// A Canvas document arrived in the text channel.
final class CanvasDocument extends ChatEvent {
  /// Creates a canvas event.
  const CanvasDocument({required this.markdown, this.title});

  /// Document body.
  final String markdown;

  /// Document title.
  final String? title;
}

/// An image was generated. Anonymous sessions never see this — `image_gen` is
/// a blocked feature — but the type exists so authenticated support is additive.
final class ImageGenerated extends ChatEvent {
  /// Creates an image event.
  const ImageGenerated(this.url);

  /// Image URL.
  final String url;
}

/// The backend answered with a different model than the one requested.
///
/// This happens silently over HTTP 200 after roughly ten turns on the top
/// model. Nothing else in the response says so.
final class ModelDowngraded extends ChatEvent {
  /// Creates a downgrade event.
  const ModelDowngraded({required this.requested, required this.actual});

  /// The model that was asked for.
  final String requested;

  /// The model that actually answered.
  final String actual;
}

/// The session hit the hourly cap and switched to a fresh device id.
///
/// Server-side conversation state is lost when this happens; prior turns are
/// replayed inline in the next prompt.
final class QuotaRotated extends ChatEvent {
  /// Creates a rotation event.
  const QuotaRotated(this.reason);

  /// Why the rotation happened.
  final String reason;
}

/// The turn finished.
final class TurnCompleted extends ChatEvent {
  /// Creates a completion event.
  const TurnCompleted({
    required this.actualModel,
    this.finishReason,
    this.limits,
  });

  /// The model that actually answered this turn.
  final String actualModel;

  /// Backend finish reason, e.g. `stop`.
  final String? finishReason;

  /// Quota state reported inline with this turn, when present.
  final Limits? limits;
}
