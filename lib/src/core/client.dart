import 'package:uuid/uuid.dart';

import 'api.dart';
import 'constants.dart';
import 'errors.dart';
import 'events.dart';
import 'models/models.dart';
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

  /// Starts a new conversation with a brand-new anonymous device id.
  ///
  /// Never resumes state from this client's [store], even if one was
  /// supplied — see [restoreSession] for that.
  ChatGptSession newSession({String systemPrompt = ''}) => ChatGptSession(
        transport: _transport,
        store: _store,
        systemPrompt: systemPrompt,
      );

  /// Starts a session, resuming the device id and conversation id last
  /// saved to this client's [store], when present. See
  /// [ChatGptSession.restore].
  Future<ChatGptSession> restoreSession({String systemPrompt = ''}) =>
      ChatGptSession.restore(
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

  /// Lists the models available to this anonymous session, with capabilities.
  ///
  /// The model list is the same for every device id, so this queries a
  /// throwaway probe id owned by this client rather than any particular
  /// session's — there is no per-device model catalogue to get wrong here,
  /// unlike [limits] (Final review, Blocker 5).
  Future<List<ModelInfo>> models() async => parseModels(
      await _transport.get('$kAnonPrefix/models', deviceId: _probeDeviceId));

  /// Reads the quota state of a throwaway probe device id this client owns
  /// — **not** any particular session's device id.
  ///
  /// Quota is tracked per `device_id`, so this always reports on an
  /// untouched device that has never sent a turn, never the spend of any
  /// [ChatGptSession] this client created (Final review, Blocker 5). Call
  /// [ChatGptSession.limits] instead to read a specific session's own
  /// standing. This method is kept for the case where only the anonymous
  /// ceilings themselves are of interest (e.g. documenting them, as the
  /// live test suite does) and no session's actual spend is being asked
  /// about.
  Future<Limits> limits() async => parseLimits(await _transport.post(
        '$kAnonPrefix/conversation/init',
        {'conversation_mode_kind': 'primary_assistant'},
        deviceId: _probeDeviceId,
      ));

  /// Translates [text] into [target]. Spends no chat message.
  ///
  /// Uses the same throwaway probe device id as [models] — translation is
  /// not scoped to any particular session's quota.
  Future<String> translate(String text,
          {required String target, String? source}) async =>
      parseTranslation(await _transport.post(
        '$kAnonPrefix/language-learning-block/translate',
        {
          'text': text,
          'target_language': target,
          if (source != null) 'source_language': source,
        },
        deviceId: _probeDeviceId,
      ));

  final String _probeDeviceId = const Uuid().v4();

  /// Releases the transport.
  void close() => _transport.close();
}
