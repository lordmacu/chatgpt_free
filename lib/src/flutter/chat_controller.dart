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

  // The pending `send()` call's completer, if a turn is in flight. Promoted
  // to a field (rather than a local in `send()`) so `stop()` and `dispose()`
  // can complete it too: cancelling a StreamSubscription never invokes
  // `onDone`/`onError`, so those two callbacks alone cannot be the only path
  // that resolves the Future `send()` handed back to its caller — otherwise
  // an `await controller.send(...)` racing a `stop()`/`dispose()` call would
  // hang forever. `_completeSend` is the single place that completes it, and
  // it always nulls the field out first, so a turn's completer can only ever
  // be completed once no matter which of the four paths (normal onDone,
  // onError, stop(), dispose()) gets there first.
  Completer<void>? _pendingSend;

  /// Model to request for each turn.
  final String model;

  /// Force web search on or off; null lets the model decide.
  final bool? webSearch;

  List<ChatMessage> _messages = const [];
  bool _isStreaming = false;
  ChatGptException? _error;
  String? _downgradeNotice;

  // The last prompt send() attempted, successful or not — retry()'s only
  // job is to resend exactly this. Recorded here rather than read back off
  // [messages] because a failed turn's user message does not survive: on
  // failure, ChatGptSession.send's own catch unwinds it out of
  // ChatGptSession.history (see session.dart) so a caller who retries the
  // same message never duplicates it — which also means there is nothing
  // left in [messages] for retry() to recover the prompt from after a
  // failure. This field is that prompt's only surviving copy.
  String? _lastPrompt;

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

    _lastPrompt = text;
    _error = null;
    _isStreaming = true;
    notifyListeners();

    final completer = Completer<void>();
    _pendingSend = completer;
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
        _completeSend();
      },
      onDone: () {
        _isStreaming = false;
        _messages = _session.history;
        notifyListeners();
        _completeSend();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Completes the in-flight `send()` call's [Completer], if there is one,
  /// exactly once. Safe to call from any of `send()`'s own callbacks, from
  /// [stop], or from [dispose] — nulling [_pendingSend] out first means a
  /// second caller sees nothing to complete.
  void _completeSend() {
    final completer = _pendingSend;
    _pendingSend = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Cancels the turn in flight.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isStreaming = false;
    notifyListeners();
    _completeSend();
  }

  /// Resends the prompt from the last [send] call that failed.
  ///
  /// A safe no-op — completes immediately without sending anything — when
  /// there is nothing to retry: no prompt has been attempted yet, the last
  /// attempt did not fail ([error] is null, so there is nothing to redo),
  /// or a turn is already streaming. This mirrors [send]'s own style of
  /// quietly ignoring a call that does not apply rather than throwing, so a
  /// "Retry" button wired straight to this method never needs a guard of
  /// its own around whether retrying currently makes sense.
  ///
  /// This exists because a failed turn leaves nothing in [messages] to
  /// retry from: [ChatGptSession.send] unwinds the user turn it staged out
  /// of history on failure (so a caller resending the same text after a
  /// failure never duplicates it), which means the prompt itself does not
  /// survive the failure anywhere the controller could read it back from.
  /// [retry] resends the prompt this controller itself remembered from the
  /// original [send] call.
  Future<void> retry() async {
    final prompt = _lastPrompt;
    if (prompt == null || _error == null || _isStreaming) return;
    return send(prompt);
  }

  /// Starts a fresh conversation.
  Future<void> clear() async {
    stop();
    await _session.reset();
    _messages = const [];
    _downgradeNotice = null;
    _error = null;
    _lastPrompt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _completeSend();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
