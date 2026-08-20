import 'errors.dart';
import 'events.dart';
import 'models/options.dart';
import 'session.dart';
import 'store.dart';
import 'transport.dart';

/// Entry point: creates sessions and owns the quota-rotation policy.
class ChatGptClient {
  /// Creates a client.
  ChatGptClient({Transport? transport, ChatGptStore? store})
      : _transport = transport ?? HttpTransport(),
        _store = store ?? InMemoryStore();

  final Transport _transport;
  final ChatGptStore _store;

  /// Starts a new conversation.
  ChatGptSession newSession({String systemPrompt = ''}) => ChatGptSession(
        transport: _transport,
        store: _store,
        systemPrompt: systemPrompt,
      );

  /// Sends a message, rotating the device id once if the hourly cap trips.
  ///
  /// A `429`/`403` is not fatal: a fresh device id clears it immediately.
  /// A silent model downgrade is *not* a rotation trigger — the backend answers
  /// 200, and throwing away conversation state to chase a model is the app's
  /// call, not the package's.
  Stream<ChatEvent> sendWithRotation(
    ChatGptSession session,
    String message, {
    SendOptions options = const SendOptions(),
    List<TextAttachment> attachments = const [],
  }) async* {
    // Deliberately `await for` + `yield`, not `yield*`: inside an async*
    // generator, `try { yield* stream; } catch (e) { ... }` does NOT catch
    // an error raised by the delegate stream — the exception escapes the
    // enclosing try/catch uncaught (verified against the Dart SDK in use;
    // `await for` does not have this problem). Using `yield*` here would
    // make the rotation logic below unreachable.
    try {
      await for (final event
          in session.send(message, options: options, attachments: attachments)) {
        yield event;
      }
      return;
    } on RateLimitedException catch (e) {
      session.rotateDevice();
      yield QuotaRotated(e.message);
    }

    try {
      await for (final event
          in session.send(message, options: options, attachments: attachments)) {
        yield event;
      }
    } on RateLimitedException catch (e) {
      throw QuotaExceededException(
          'quota still exhausted after rotating the device: ${e.message}');
    }
  }

  /// Releases the transport.
  void close() => _transport.close();
}
