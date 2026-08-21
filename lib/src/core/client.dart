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
  ///
  /// [maxRotations] caps how many times [sendWithRotation] will rotate the
  /// device id and retry after an hourly-cap rejection before giving up
  /// with [QuotaExceededException]. Defaults to 1 (rotate once, retry
  /// once) so existing callers see no behaviour change. Rotating clears
  /// the cap immediately in the common case, but the cap also has an IP
  /// component — measured runs from the same IP tripped it again after as
  /// few as 31 messages on a device that had just rotated, sometimes as
  /// many as 45 — so under sustained load a freshly rotated device can be
  /// born already limited. Raise this for an app that would rather spend a
  /// few more device ids than surface [QuotaExceededException] under that
  /// kind of load.
  ChatGptClient({
    Transport? transport,
    ChatGptStore? store,
    this.maxRotations = 1,
  })  : _transport = transport ?? HttpTransport(),
        _store = store ?? InMemoryStore();

  final Transport _transport;
  final ChatGptStore _store;

  /// How many times [sendWithRotation] rotates the device id and retries
  /// before giving up with [QuotaExceededException]. See the constructor's
  /// doc comment.
  final int maxRotations;

  /// Starts a new conversation with a brand-new anonymous device id.
  ///
  /// Never resumes state from this client's [store], even if one was
  /// supplied — see [restoreSession] for that.
  ChatGptSession newSession({String systemPrompt = ''}) => ChatGptSession(
        transport: _transport,
        store: _store,
        systemPrompt: systemPrompt,
      );

  /// Starts a session that never touches this client's store.
  ///
  /// For work that is not the user's conversation — a one-shot extraction, a
  /// probe — where persisting a throwaway device id would overwrite the real
  /// one the app resumes from. Shares the client's transport, and its quota:
  /// an ephemeral session is a different device, so it starts with an
  /// untouched hourly allowance of its own.
  ChatGptSession newEphemeralSession({String systemPrompt = ''}) =>
      ChatGptSession(
        transport: _transport,
        store: InMemoryStore(),
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

  /// Sends a message, rotating the device id up to [maxRotations] times if
  /// the hourly cap trips.
  ///
  /// A `429`/`403` is not fatal: a fresh device id clears it immediately in
  /// the common case. A silent model downgrade is *not* a rotation trigger
  /// — the backend answers 200, and throwing away conversation state to
  /// chase a model is the app's call, not the package's.
  Stream<ChatEvent> sendWithRotation(
    ChatGptSession session,
    String message, {
    SendOptions options = const SendOptions(),
    List<TextAttachment> attachments = const [],
  }) async* {
    var rotations = 0;
    while (true) {
      // Deliberately `await for` + `yield`, not `yield*`: inside an async*
      // generator, `try { yield* stream; } catch (e) { ... }` does NOT
      // catch an error raised by the delegate stream — the exception
      // escapes the enclosing try/catch uncaught (verified against the
      // Dart SDK in use; `await for` does not have this problem). Using
      // `yield*` here would make the rotation logic below unreachable.
      try {
        await for (final event in session.send(message,
            options: options, attachments: attachments)) {
          yield event;
        }
        return;
      } on RateLimitedException catch (e) {
        if (rotations >= maxRotations) {
          throw QuotaExceededException('quota still exhausted after $rotations '
              '${rotations == 1 ? 'rotation' : 'rotations'}: ${e.message}');
        }
        rotations++;
        session.rotateDevice();
        yield QuotaRotated(e.message);
      }
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
          // camelCase, unlike every other endpoint in this API. Sending
          // `target_language` is HTTP 422 "Field required: targetLanguageCode"
          // — the translate service does not share the conversation
          // endpoint's snake_case convention.
          'text': text,
          'targetLanguageCode': target,
          if (source != null) 'sourceLanguageCode': source,
        },
        deviceId: _probeDeviceId,
      ));

  final String _probeDeviceId = const Uuid().v4();

  /// Releases the transport.
  void close() => _transport.close();
}
