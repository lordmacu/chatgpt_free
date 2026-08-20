import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/client.dart';
import '../core/errors.dart';
import '../core/events.dart';
import '../core/models/models.dart';
import '../core/models/options.dart';
import '../core/session.dart';

/// Drives a chat transcript. Plain [ChangeNotifier], so it works with Riverpod,
/// Bloc, Provider or a bare `AnimatedBuilder` — no state management imposed.
class ChatController extends ChangeNotifier {
  /// Creates a controller.
  ChatController({
    ChatGptClient? client,
    String systemPrompt = '',
    this.model = 'auto',
    this.webSearch,
  })  : _client = client ?? ChatGptClient(),
        _ownsClient = client == null {
    _session = _client.newSession(systemPrompt: systemPrompt);
  }

  final ChatGptClient _client;
  final bool _ownsClient;
  late ChatGptSession _session;
  StreamSubscription<ChatEvent>? _subscription;

  /// Model to request for each turn.
  final String model;

  /// Force web search on or off; null lets the model decide.
  final bool? webSearch;

  List<ChatMessage> _messages = const [];
  bool _isStreaming = false;
  ChatGptException? _error;
  String? _downgradeNotice;

  /// The transcript.
  List<ChatMessage> get messages => _messages;

  /// True while a reply is streaming.
  bool get isStreaming => _isStreaming;

  /// The last error, if any.
  ChatGptException? get error => _error;

  /// Set when the backend answered with a different model than requested.
  String? get downgradeNotice => _downgradeNotice;

  /// Sends [text] and streams the reply into [messages].
  Future<void> send(String text) async {
    if (_isStreaming || text.trim().isEmpty) return;

    _error = null;
    _isStreaming = true;
    notifyListeners();

    final completer = Completer<void>();
    _subscription = _client
        .sendWithRotation(
          _session,
          text,
          options: SendOptions(model: model, webSearch: webSearch),
        )
        .listen(
      (event) {
        if (event is ModelDowngraded) {
          _downgradeNotice =
              'Requested ${event.requested}, answered by ${event.actual}.';
        }
        _messages = _session.history;
        notifyListeners();
      },
      onError: (Object e) {
        _error = e is ChatGptException ? e : TransportException('$e');
        _isStreaming = false;
        _messages = _session.history;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        _isStreaming = false;
        _messages = _session.history;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Cancels the turn in flight.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isStreaming = false;
    notifyListeners();
  }

  /// Starts a fresh conversation.
  Future<void> clear() async {
    stop();
    await _session.reset();
    _messages = const [];
    _downgradeNotice = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
