import 'package:uuid/uuid.dart';

import 'events.dart';
import 'models/models.dart';
import 'models/options.dart';
import 'request_body.dart';
import 'sse/reader.dart';
import 'sse/turn_parser.dart';
import 'store.dart';
import 'transport.dart';

const Uuid _uuid = Uuid();

/// Legacy OpenAI model ids mapped onto real backend slugs.
const Map<String, String> _modelAliases = {
  'gpt-4o': 'auto',
  'gpt-4o-mini': 'gpt-5-3-mini',
  'gpt-4': 'gpt-5-5',
  'gpt-3.5-turbo': 'gpt-5-3-mini',
};

/// One anonymous conversation: a device id, a conversation id, and the turns
/// exchanged so far.
class ChatGptSession {
  /// Creates a session.
  ChatGptSession({
    Transport? transport,
    ChatGptStore? store,
    this.systemPrompt = '',
    String? deviceId,
  })  : _transport = transport ?? HttpTransport(),
        _ownsTransport = transport == null,
        _store = store ?? InMemoryStore(),
        _deviceId = deviceId ?? _uuid.v4();

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
  /// next prompt replays [history] inline.
  void rotateDevice() {
    _deviceId = _uuid.v4();
    _conversationId = null;
    _parentMessageId = null;
    _firstTurn = true;
  }

  /// Clears everything, including local history.
  Future<void> reset() async {
    rotateDevice();
    _history.clear();
    await _store.delete('conversation_id');
  }

  /// Sends [message] and streams the turn's events.
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
      kAnonPrefixConversationPath,
      body,
      deviceId: _deviceId,
    );

    // From here the turn is staged: _firstTurn is spent and _history holds a
    // user turn plus a streaming assistant placeholder. A stream that throws
    // mid-turn (dropped connection, malformed frame) must not leave that
    // placeholder behind for the next send() to fold into its prompt as
    // "prior conversation" — so everything from here to the end of the turn
    // is wrapped in try/catch: on any failure, undo exactly what this call
    // staged and restore _firstTurn, then rethrow. A caller that retries the
    // same message after any failure — before the transport call or mid-
    // stream — sees history exactly as if this attempt never happened.
    _firstTurn = false;
    _history.add(ChatMessage(role: 'user', text: message));
    _history.add(const ChatMessage(
        role: 'assistant', text: '', isStreaming: true));

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
          _history[_history.length - 1] =
              _history.last.copyWith(text: assembled);
        } else if (event is CitationsReceived) {
          citations = event.citations;
        }
        yield event;
      }
    } catch (_) {
      _history.removeLast(); // the streaming assistant placeholder
      _history.removeLast(); // this turn's user message
      _firstTurn = sendingSystemPrompt;
      rethrow;
    }

    _history[_history.length - 1] = _history.last
        .copyWith(citations: citations, isStreaming: false);

    if (parser.conversationId.isNotEmpty) {
      _conversationId = parser.conversationId;
      await _store.write('conversation_id', parser.conversationId);
    }
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
const String kAnonPrefixConversationPath = '/backend-anon/f/conversation';
