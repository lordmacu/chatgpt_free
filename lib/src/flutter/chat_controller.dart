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
///
/// Note on exceptions: the [model] and [webSearch] setters throw a plain
/// `StateError` (from `dart:core`), not a [ChatGptException], when called
/// while [isStreaming] is true — see [model]'s doc comment. A blanket
/// `on ChatGptException catch (e) { ... }` around UI code that also calls
/// these setters will not catch that; guard the setter call itself instead
/// (e.g. disable the control while [isStreaming] is true).
class ChatController extends ChangeNotifier {
  /// Creates a controller.
  ChatController({
    ChatGptClient? client,
    String systemPrompt = '',
    String model = 'auto',
    bool? webSearch,
  })  : _client = client ?? ChatGptClient(),
        _ownsClient = client == null,
        _model = model,
        _webSearch = webSearch {
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

  // Backing fields for [model] and [webSearch]. Both are mutable (unlike
  // the rest of this controller's settings, which are constructor-only)
  // specifically so a UI model picker / web-search toggle can drive them —
  // see the setters below for the precedence and streaming-guard rules
  // that make that safe.
  String _model;
  bool? _webSearch;

  /// Model requested for a turn that does not pass its own [SendOptions] to
  /// [send] — see [send]'s doc comment for the exact precedence rule.
  ///
  /// Settable: assigning a new value does not touch [messages] or the
  /// underlying session, so switching models mid-conversation keeps the
  /// transcript and the server-side `conversation_id` intact — only later
  /// turns pick up the new model. The setter throws [StateError] while
  /// [isStreaming] is true; see its own doc comment for why.
  String get model => _model;

  set model(String value) {
    _guardAgainstStreamingMutation('model');
    _model = value;
    notifyListeners();
  }

  /// Force web search on or off for a turn that does not pass its own
  /// [SendOptions] to [send]; null lets the model decide. See [model] for
  /// the mutability, conversation-continuity and streaming-guard notes —
  /// they apply identically here.
  bool? get webSearch => _webSearch;

  set webSearch(bool? value) {
    _guardAgainstStreamingMutation('webSearch');
    _webSearch = value;
    notifyListeners();
  }

  // Shared guard for the [model] and [webSearch] setters. Throwing here
  // (rather than silently applying the change, or silently queueing it)
  // is documented on [model] and [webSearch]; see also the doc comment on
  // [isStreaming].
  void _guardAgainstStreamingMutation(String setterName) {
    if (_isStreaming) {
      throw StateError(
          'ChatController.$setterName cannot be changed while a turn is '
          'streaming (isStreaming == true). The change can never reach '
          "the turn already in flight — its SendOptions were built and "
          'sent before this call — so applying it silently would leave '
          "the controller's reported setting disagreeing with what "
          'actually produced the reply on screen. Wait for the turn to '
          'finish (or call stop()) before changing it, e.g. by disabling '
          'the control that calls this setter while isStreaming is true.');
    }
  }

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
  ///
  /// While this is true, the [model] and [webSearch] setters throw
  /// [StateError] rather than change the running turn's settings out from
  /// under it — see [model]'s doc comment.
  bool get isStreaming => _isStreaming;

  /// The last error, if any.
  ChatGptException? get error => _error;

  /// Set when the backend answered with a different model than requested.
  String? get downgradeNotice => _downgradeNotice;

  /// The [SendOptions] a call to [send] that omits its own [options]
  /// argument would build for the *next* turn: `SendOptions(model: model,
  /// webSearch: webSearch)`, read fresh from this controller's current
  /// [model] and [webSearch] every time this getter is read (not cached),
  /// so it reflects a setter call made moments — or a frame — earlier.
  ///
  /// This is the required starting point for a one-off per-turn override,
  /// specifically to avoid the footgun [send]'s own doc comment warns
  /// about: because an explicit [SendOptions] passed to [send] is used
  /// verbatim, building one from scratch — `const SendOptions(canvas:
  /// true)` — silently sends `model: 'auto'` (`SendOptions`' own default)
  /// even while a model picker bound to [model] still shows something
  /// else selected, with nothing surfacing the mismatch: `ModelDowngraded`
  /// compares the *requested* model against the answering one, so a
  /// self-inflicted `'auto'` substitution here looks exactly like a
  /// correct request for `'auto'`. Start from this getter instead:
  /// `controller.send(text, options: controller.currentOptions.copyWith(canvas:
  /// true))` changes only `canvas` for that turn and keeps whatever model
  /// is actually selected.
  SendOptions get currentOptions =>
      SendOptions(model: _model, webSearch: _webSearch);

  /// Sends [text] and streams the reply into [messages].
  ///
  /// [options] and [attachments] are per-turn, mirroring
  /// [ChatGptSession.send]/[ChatGptClient.sendWithRotation] directly.
  ///
  /// Precedence between [options] and this controller's own [model] /
  /// [webSearch]: **[options], when supplied, is used exactly as given —
  /// it is never merged with the controller's settings.** If [options] is
  /// omitted (the default, and the only form that existed before this
  /// parameter was added), this turn uses [currentOptions] — built fresh
  /// from the controller's current [model] and [webSearch] at the moment
  /// [send] is called. There is no field-by-field fallback in either
  /// direction: a caller who passes `SendOptions(model: 'gpt-5-6')` gets
  /// `webSearch: null` for that turn (SendOptions' own default) even if
  /// `this.webSearch` is `true` — not the controller's value quietly
  /// filled in. This keeps the rule predictable from the call site alone:
  /// pass [options] and it is the whole story for that turn; omit it and
  /// the controller's current settings are the whole story.
  ///
  /// **Do not build a per-turn [options] override from a bare `SendOptions(...)`
  /// literal** — that drops [model] back to `SendOptions`' own `'auto'`
  /// default, invisibly, because verbatim precedence means nothing fills
  /// it back in. Extend [currentOptions] instead:
  /// `controller.send(text, options: controller.currentOptions.copyWith(canvas: true))`.
  /// See [currentOptions]'s doc comment for why this matters.
  Future<void> send(
    String text, {
    SendOptions? options,
    List<TextAttachment> attachments = const [],
  }) async {
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
      options: options ?? currentOptions,
      attachments: attachments,
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

  /// Re-fetches this conversation from the backend, replacing the transcript.
  ///
  /// Anonymous conversations cannot be listed, but one CAN be read back by id
  /// from the device that created it — so an app that switched away and back
  /// can restore the real transcript instead of trusting a local copy.
  /// A no-op while a turn is streaming, and when no conversation exists yet.
  ///
  /// Returns the backend's title for the conversation, when it has one.
  Future<String?> loadHistory() async {
    if (_isStreaming) return null;
    try {
      final detail = await _session.loadHistory();
      _messages = _session.history;
      _error = null;
      notifyListeners();
      return detail?.title;
    } on ChatGptException catch (e) {
      _error = e;
      notifyListeners();
      return null;
    }
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
