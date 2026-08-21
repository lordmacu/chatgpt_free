import 'models/models.dart';

/// Everything that can happen during one turn.
sealed class ChatEvent {
  /// Creates an event.
  const ChatEvent();
}

/// A chunk of assistant text, already stripped of PUA markers.
///
/// Under normal streaming this is additive: a consumer builds the reply by
/// appending [text] to whatever it already has. The wire protocol allows a
/// `replace` or `truncate` on the text channel at any point, though — the
/// backend editing text it already streamed. No purely additive delta can
/// express "forget what you have and use this instead", so when that
/// happens [isReset] is true and [text] is the complete, corrected reply
/// so far, not a suffix to append. A consumer that folds every [TextDelta]
/// — starting from `''`, replacing its running text with [text] when
/// [isReset] is true and appending it otherwise — always ends the turn
/// with exactly the text the backend ended it with.
final class TextDelta extends ChatEvent {
  /// Creates a text delta. [isReset] defaults to false, the common
  /// append-only case.
  const TextDelta(this.text, {this.isReset = false});

  /// The new text — append it, unless [isReset] is true.
  final String text;

  /// True when [text] is a full replacement for the reply so far (the
  /// backend edited already-streamed text), not a suffix to append.
  final bool isReset;
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

/// The backend named the conversation.
///
/// It arrives on the same stream as the reply, a beat after the last text
/// delta — so a UI can title a conversation the moment it is created, without
/// fetching it back. The backend sometimes refines its first guess and sends a
/// second one; the last one for a turn is the title it kept.
final class ConversationTitled extends ChatEvent {
  /// Creates a title event.
  const ConversationTitled(this.title);

  /// The generated title.
  final String title;
}

/// The assistant finished writing, but the stream is still open.
///
/// The backend keeps sending after the last text delta — it generates the
/// conversation title, then the quota snapshot — which measured at about five
/// seconds on a real turn. A UI that waits for [TurnCompleted] to stop its
/// typing indicator therefore looks stuck long after the answer is on screen.
/// Stop the indicator here; keep the composer disabled until [TurnCompleted],
/// because the session still has the turn open.
final class ReplyCompleted extends ChatEvent {
  /// Creates a reply-finished event.
  const ReplyCompleted();
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

/// The whole reply of a turn, as one string.
///
/// The backend has no non-streaming mode — it answers `text/event-stream`
/// whatever you ask for, verified against `force_use_sse: false`,
/// `stream: false` and `Accept: application/json`. What it does not require
/// is that you CONSUME the answer incrementally, and most callers do not want
/// to.
///
/// Use this on any [ChatEvent] stream, including
/// [ChatGptClient.sendWithRotation], when you want the finished text rather
/// than the typing:
///
/// ```dart
/// final reply = await collectText(client.sendWithRotation(session, 'hola'));
/// ```
///
/// It exists mainly to own the one way this is easy to get wrong. A
/// [TextDelta] with `isReset` means the backend replaced what it had already
/// streamed, so appending every delta duplicates text the backend just
/// discarded. That shipped as a real bug once.
Future<String> collectText(Stream<ChatEvent> events) async {
  final buffer = StringBuffer();
  await for (final event in events) {
    if (event is TextDelta) {
      if (event.isReset) {
        buffer
          ..clear()
          ..write(event.text);
      } else {
        buffer.write(event.text);
      }
    }
  }
  return buffer.toString();
}
