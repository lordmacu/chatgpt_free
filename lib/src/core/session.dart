import 'dart:async';

import 'package:uuid/uuid.dart';

import 'api.dart';
import 'constants.dart';
import 'events.dart';
import 'models/models.dart';
import 'models/options.dart';
import 'request_body.dart';
import 'sse/reader.dart';
import 'sse/turn_parser.dart';
import 'store.dart';
import 'transport.dart';

const Uuid _uuid = Uuid();

/// Store key under which [device] id's own conversation id is kept.
///
/// Final review, Finding 6: [ChatGptClient] shares one [ChatGptStore]
/// across every session it creates, and both `device_id` and
/// `conversation_id` used to be bare, unnamespaced keys. Two sessions from
/// one client sharing a persistent store (e.g. two chat tabs) could
/// interleave their writes so that session B's device id ended up saved
/// alongside session A's conversation id — a pairing the backend never
/// created and that [restore] had no way to detect, since it could only
/// check presence, not provenance. Scoping the conversation id key by the
/// device id it was learned under closes that: [restore] can only ever
/// resume a conversation id from the exact device id key it was written
/// under, so a conversation id from one device can never be handed back
/// paired with another device's id. `device_id` itself stays a single bare
/// key — last-write-wins there is pre-existing, documented behaviour (this
/// store holds one "current" identity), not the bug being fixed.
String _conversationStoreKey(String deviceId) => 'conversation_id:$deviceId';

/// Legacy OpenAI model ids mapped onto real backend slugs.
const Map<String, String> _modelAliases = {
  'gpt-4o': 'auto',
  'gpt-4o-mini': 'gpt-5-3-mini',
  'gpt-4': 'gpt-5-5',
  'gpt-3.5-turbo': 'gpt-5-3-mini',
};

/// One anonymous conversation: a device id, a conversation id, and the turns
/// exchanged so far. Overlapping [send] calls on one session are
/// unsupported — create one session per concurrent conversation instead.
class ChatGptSession {
  /// Creates a session with a brand-new anonymous device id.
  ///
  /// This constructor never reads from [store], even when one is supplied —
  /// only [ChatGptSession.restore] does. A constructor that silently resumed
  /// whatever device id and conversation happened to be sitting in [store]
  /// would be a trap: every plain `ChatGptSession(store: ...)` call would
  /// then quietly continue someone else's — or last run's own — abandoned
  /// conversation instead of starting one, with nothing at the call site to
  /// suggest that. Restoration is opt-in; call [ChatGptSession.restore]
  /// when that is actually what you want.
  ///
  /// This constructor does still *write* its fresh device id to [store]
  /// (fire-and-forget — the constructor stays synchronous), so a later
  /// [ChatGptSession.restore] call has something to find.
  ChatGptSession({
    Transport? transport,
    ChatGptStore? store,
    this.systemPrompt = '',
    String? deviceId,
  })  : _transport = transport ?? HttpTransport(),
        _ownsTransport = transport == null,
        _store = store ?? InMemoryStore(),
        _deviceId = deviceId ?? _uuid.v4() {
    unawaited(_store.write('device_id', _deviceId));
  }

  /// Creates a session, resuming the device id and conversation id last
  /// saved to [store], when both are present there.
  ///
  /// This is the opt-in counterpart to the plain constructor: call this
  /// instead when you *want* to continue whatever conversation was last
  /// persisted — e.g. to keep the same device id, and therefore the same
  /// per-model quota bucket, across app restarts. Falls back to a fresh
  /// device id and no conversation — exactly like the plain constructor —
  /// when [store] has nothing saved yet.
  static Future<ChatGptSession> restore({
    Transport? transport,
    required ChatGptStore store,
    String systemPrompt = '',
  }) async {
    // A store returning '' for an absent key (some real-world adapters do)
    // must be treated exactly like null — otherwise an empty string sails
    // past the `!= null` check below, becomes this session's device id, and
    // ends up on the wire as an empty `OAI-Device-Id` header with no
    // recovery path (Final review, minor).
    final rawDeviceId = await store.read('device_id');
    final savedDeviceId =
        (rawDeviceId != null && rawDeviceId.isNotEmpty) ? rawDeviceId : null;

    // Only look up (and only ever resume) a conversation id under the saved
    // device id's own namespaced key — see [_conversationStoreKey]. A
    // conversation id is meaningless (or worse, wrong) paired with a device
    // id the backend never saw it on, and this key scheme makes that
    // pairing structurally unreachable rather than merely checked for.
    String? savedConversationId;
    if (savedDeviceId != null) {
      final rawConversationId =
          await store.read(_conversationStoreKey(savedDeviceId));
      savedConversationId =
          (rawConversationId != null && rawConversationId.isNotEmpty)
              ? rawConversationId
              : null;
    }

    final session = ChatGptSession(
      transport: transport,
      store: store,
      systemPrompt: systemPrompt,
      deviceId: savedDeviceId,
    );
    if (savedConversationId != null) {
      session._conversationId = savedConversationId;
    }
    return session;
  }

  final Transport _transport;

  /// True when this session created [_transport] itself (no transport was
  /// injected). An injected transport may be shared — e.g. one HttpTransport
  /// reused across every session a client-layer wrapper creates — so [close]
  /// must only release a transport this session owns.
  final bool _ownsTransport;
  final ChatGptStore _store;

  /// Instructions injected on the first turn of the conversation.
  final String systemPrompt;

  String _deviceId;
  String? _conversationId;
  String? _parentMessageId;
  bool _firstTurn = true;
  final List<ChatMessage> _history = [];

  /// The device id this session identifies as.
  String get deviceId => _deviceId;

  /// The server-side conversation id, once the backend has issued one.
  String? get conversationId => _conversationId;

  /// Turns exchanged in this session.
  List<ChatMessage> get history => List.unmodifiable(_history);

  /// Abandons the current device id and conversation, keeping local history.
  ///
  /// Called after the hourly cap trips. Server-side context is gone, so the
  /// next prompt replays [history] inline. The new device id is persisted to
  /// the store (fire-and-forget — this method stays synchronous so
  /// [ChatGptClient.sendWithRotation] can call it inline mid-stream) so a
  /// later [ChatGptSession.restore] picks up the rotated identity rather
  /// than the abandoned one. The old device id's own conversation-id entry
  /// is also deleted (best-effort hygiene — the new device id's own entry
  /// was simply never written, so [restore] would already find nothing for
  /// it either way; see [_conversationStoreKey]).
  void rotateDevice() {
    final abandonedDeviceId = _deviceId;
    _deviceId = _uuid.v4();
    _conversationId = null;
    _parentMessageId = null;
    _firstTurn = true;
    unawaited(_store.write('device_id', _deviceId));
    unawaited(_store.delete(_conversationStoreKey(abandonedDeviceId)));
  }

  /// Clears everything, including local history and persisted state.
  Future<void> reset() async {
    final abandonedDeviceId = _deviceId;
    rotateDevice();
    _history.clear();
    // rotateDevice()'s own writes above are fire-and-forget; redo them here,
    // awaited, so the store is guaranteed to reflect the reset by the time
    // this Future completes.
    await _store.delete(_conversationStoreKey(abandonedDeviceId));
    await _store.write('device_id', _deviceId);
  }

  /// Reads the current quota state for *this session's own* device id,
  /// without sending a message.
  ///
  /// Quota is tracked per `device_id` — that is the entire premise of the
  /// rotation feature — so this is the source of truth for what this
  /// session itself has spent. [ChatGptClient.limits] cannot answer that:
  /// it queries a throwaway probe id no turn has ever run under, so it
  /// always reports an untouched device, never this session's real
  /// standing (Final review, Blocker 5). If this session has just
  /// [rotateDevice]d, this reports the fresh device's — necessarily
  /// unspent — quota, which is correct: the old device's spend is exactly
  /// what rotation left behind.
  Future<Limits> limits() async => parseLimits(await _transport.post(
        '$kAnonPrefix/conversation/init',
        {'conversation_mode_kind': 'primary_assistant'},
        deviceId: _deviceId,
      ));

  /// Sends [message] and streams the turn's events.
  ///
  /// If this call fails, the entries it staged in [history] (the user turn
  /// and the streaming assistant placeholder) are removed by identity, so a
  /// failure in this call can never disturb entries a different, overlapping
  /// call has staged of its own. That is the only concurrency guarantee this
  /// method makes.
  ///
  /// Calling [send] again before a previous call's stream has finished is
  /// unsupported. Two overlapping calls degrade the session in ways nothing
  /// here guards against: both may read [systemPrompt] as still pending and
  /// so send it on more than one turn, and both may read [conversationId] as
  /// unset and go out as a new conversation — whichever finishes last then
  /// silently overwrites [conversationId], orphaning the other call's
  /// conversation branch on the backend with no way to reference it again.
  /// For concurrent conversations, create one [ChatGptSession] per
  /// conversation rather than overlapping calls to [send] on a single one.
  Stream<ChatEvent> send(
    String message, {
    SendOptions options = const SendOptions(),
    List<TextAttachment> attachments = const [],
  }) async* {
    options.validate();

    final model = _modelAliases[options.model] ?? options.model;
    final prompt = _conversationId == null && _history.isNotEmpty
        ? _withReplayedHistory(message)
        : message;

    // Read, don't mutate: _firstTurn is only flipped once the turn actually
    // starts (see below), so a throw building the body or a synchronously
    // rejected transport call leaves it exactly as it was for the retry.
    final sendingSystemPrompt = _firstTurn;
    final body = buildConversationBody(
      message: prompt,
      model: model,
      options: options,
      conversationId: _conversationId,
      parentMessageId: _parentMessageId,
      fileTexts: [
        for (final a in attachments) '${a.name}\n${a.content}',
      ],
      systemPrompt: sendingSystemPrompt ? systemPrompt : null,
    );

    // The request goes out BEFORE the turn is recorded. A rate limit throws
    // here, the client rotates and calls send() again with the same message —
    // recording earlier would duplicate the user turn on every retry. Nothing
    // above this line has mutated session state, so that throw needs no
    // unwinding: the session is already exactly as a retry expects it.
    final bytes = await _transport.stream(
      _kAnonPrefixConversationPath,
      body,
      deviceId: _deviceId,
    );

    // From here the turn is staged: _firstTurn is spent and _history holds a
    // user turn plus a streaming assistant placeholder. There is no
    // reentrancy guard on send() — an earlier attempt at one could brick a
    // session forever if a caller abandoned an in-flight stream without
    // draining it (see Fix round 3 in the task report), which is worse than
    // the corruption it prevented. So two overlapping send() calls on the
    // same session ARE possible, and this call's two _history entries below
    // are tracked by *identity* (via [_updateHistoryEntry] /
    // [_removeHistoryEntry], both keyed with identical()) rather than by
    // position, everywhere they are touched again. Position (`_history.last`
    // / `removeLast()`) is never safe here: another call can append its own
    // entries after this call's, or after this call's own entries are
    // updated in place by a delta.
    //
    // That identity tracking covers _history only. _firstTurn and
    // _conversationId are plain scalars with no equivalent guard: two
    // overlapping calls can both read _firstTurn as true and both send the
    // system prompt, and can both read _conversationId as null and both go
    // out as a new conversation, with whichever finishes last overwriting
    // it. See send()'s doc comment — overlapping calls are unsupported for
    // exactly this reason; this method only promises that a failure cannot
    // corrupt another call's _history entries.
    //
    // A stream that throws mid-turn (dropped connection, malformed frame)
    // must not leave this call's placeholder behind for the next send() to
    // fold into its prompt as "prior conversation" — so everything from here
    // to the end of the turn is wrapped in try/catch: on any failure, undo
    // exactly (and only) what this call staged, by identity, and restore
    // this call's own _firstTurn state, then rethrow. A caller that retries
    // the same message after any failure — before the transport call or
    // mid-stream — sees its own staged _history entries removed exactly as
    // if this attempt never happened; entries any other call has staged are
    // untouched, because they were never this call's to begin with.
    _firstTurn = false;
    final userTurn = ChatMessage(role: 'user', text: message);
    // Deliberately not `const`: two overlapping calls must get distinct
    // object identities here, since everything below locates this call's
    // own placeholder with identical(). A const literal would canonicalize
    // to one shared instance across every call with these exact field
    // values, defeating that entirely.
    // ignore: prefer_const_constructors
    var assistantTurn = ChatMessage(role: 'assistant', text: '', isStreaming: true);
    _history.add(userTurn);
    _history.add(assistantTurn);

    final parser = TurnParser(requestedModel: options.model);
    var assembled = '';
    var citations = const <Citation>[];

    try {
      await for (final event in parser.parse(readSse(bytes))) {
        if (event is TextDelta) {
          // Fold, never concatenate. isReset means the backend replaced or
          // truncated the reply mid-stream (a `replace`/`truncate` delta on
          // the text path); appending there would duplicate what it
          // discarded.
          assembled = event.isReset ? event.text : assembled + event.text;
          assistantTurn = _updateHistoryEntry(
              assistantTurn, assistantTurn.copyWith(text: assembled));
        } else if (event is CitationsReceived) {
          citations = event.citations;
        }
        yield event;
      }
    } catch (_) {
      _removeHistoryEntry(assistantTurn); // this call's streaming placeholder
      _removeHistoryEntry(userTurn); // this call's user message
      _firstTurn = sendingSystemPrompt;
      rethrow;
    }

    assistantTurn = _updateHistoryEntry(assistantTurn,
        assistantTurn.copyWith(citations: citations, isStreaming: false));

    if (parser.conversationId.isNotEmpty) {
      _conversationId = parser.conversationId;
      // Namespaced by this session's own device id — see
      // [_conversationStoreKey] — so [restore] can never hand this
      // conversation id back paired with a different device id.
      await _store.write(_conversationStoreKey(_deviceId), parser.conversationId);
    }
  }

  /// Replaces [oldEntry] in [_history] with [newEntry], locating it by
  /// identity — never by position, since another overlapping [send] call may
  /// have appended entries of its own after it. Returns [newEntry] so the
  /// caller can keep tracking it under its latest identity. A no-op (still
  /// returns [newEntry]) if [oldEntry] is no longer present, e.g. this
  /// call's own catch block already removed it.
  ChatMessage _updateHistoryEntry(ChatMessage oldEntry, ChatMessage newEntry) {
    final index = _history.indexWhere((m) => identical(m, oldEntry));
    if (index != -1) _history[index] = newEntry;
    return newEntry;
  }

  /// Removes [entry] from [_history], located by identity. A no-op if it is
  /// already gone.
  void _removeHistoryEntry(ChatMessage entry) {
    final index = _history.indexWhere((m) => identical(m, entry));
    if (index != -1) _history.removeAt(index);
  }

  String _withReplayedHistory(String message) {
    final turns = _history
        .map((m) => '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.text}')
        .join('\n');
    return '[Prior conversation — use this as context:\n$turns\n]\n\n$message';
  }

  /// Releases the transport, but only if this session created it itself.
  /// An injected transport may be shared by its owner (e.g. across every
  /// session a client-layer wrapper creates) and must be closed by whoever
  /// owns it, not by an individual session using it.
  void close() {
    if (_ownsTransport) _transport.close();
  }
}

/// Path of the anonymous conversation endpoint.
///
/// Private: this is an implementation detail of [ChatGptSession.send], not
/// part of the public surface — a consumer has no legitimate use for it.
const String _kAnonPrefixConversationPath = '/backend-anon/f/conversation';
