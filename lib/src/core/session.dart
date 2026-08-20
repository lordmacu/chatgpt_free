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
        _store = store ?? InMemoryStore(),
        _deviceId = deviceId ?? _uuid.v4();

  final Transport _transport;
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

    final body = buildConversationBody(
      message: prompt,
      model: model,
      options: options,
      conversationId: _conversationId,
      parentMessageId: _parentMessageId,
      fileTexts: [
        for (final a in attachments) '${a.name}\n${a.content}',
      ],
      systemPrompt: _firstTurn ? systemPrompt : null,
    );
    _firstTurn = false;

    // The request goes out BEFORE the turn is recorded. A rate limit throws
    // here, the client rotates and calls send() again with the same message —
    // recording earlier would duplicate the user turn on every retry.
    final bytes = await _transport.stream(
      kAnonPrefixConversationPath,
      body,
      deviceId: _deviceId,
    );

    _history.add(ChatMessage(role: 'user', text: message));

    final parser = TurnParser(requestedModel: options.model);
    var assembled = '';
    var citations = const <Citation>[];

    _history.add(const ChatMessage(
        role: 'assistant', text: '', isStreaming: true));

    await for (final event in parser.parse(readSse(bytes))) {
      if (event is TextDelta) {
        // Fold, never concatenate. isReset means the backend replaced or
        // truncated the reply mid-stream (a `replace`/`truncate` delta on the
        // text path); appending there would duplicate what it discarded.
        assembled = event.isReset ? event.text : assembled + event.text;
        _history[_history.length - 1] =
            _history.last.copyWith(text: assembled);
      } else if (event is CitationsReceived) {
        citations = event.citations;
      }
      yield event;
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

  /// Releases the transport.
  void close() => _transport.close();
}

/// Path of the anonymous conversation endpoint.
const String kAnonPrefixConversationPath = '/backend-anon/f/conversation';
