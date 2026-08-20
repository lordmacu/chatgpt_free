import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// Model ids the anonymous backend actually serves, most to least capable.
const List<String> kAvailableModels = [
  'auto',
  'gpt-5-6',
  'gpt-5-5',
  'gpt-5-6-mini',
  'gpt-5-5-mini',
  'gpt-5-3-mini',
];

/// Demo app: a chat with no API key and no account.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'chatgpt_free',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B899)),
          useMaterial3: true,
        ),
        home: const ChatScreen(),
      );
}

/// The one screen this demo has.
class ChatScreen extends StatefulWidget {
  /// Creates the screen.
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // The example owns the client so it can reach the core API — translate()
  // in particular, which the Flutter layer does not wrap because it is not
  // part of a chat turn (and notably spends no message from the quota).
  final ChatGptClient _client = ChatGptClient();
  late final ChatController _controller = ChatController(
    client: _client,
    systemPrompt: 'Answer briefly.',
  );

  @override
  void dispose() {
    _controller.dispose();
    // The controller only closes a client it created itself, so this one is
    // ours to close.
    _client.close();
    super.dispose();
  }

  String? get _lastReply {
    for (final m in _controller.messages.reversed) {
      if (m.role == 'assistant' && m.text.trim().isNotEmpty) return m.text;
    }
    return null;
  }

  Future<void> _translateLastReply() async {
    final reply = _lastReply;
    final messenger = ScaffoldMessenger.of(context);
    if (reply == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to translate yet.')),
      );
      return;
    }
    try {
      final english = await _client.translate(reply, target: 'en');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Translated to English'),
          content: SingleChildScrollView(child: SelectableText(english)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on ChatGptException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        // Rebuilds the app bar too (not just ChatView) so the model picker
        // and web-search toggle below can grey themselves out while a turn
        // is streaming — ChatController.model/webSearch throw StateError if
        // set at that point, since the change could never reach the reply
        // already in flight. Disabling the controls is how this example
        // avoids ever hitting that guard.
        animation: _controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('chatgpt_free'),
            actions: [
              // isSelected + a filled style, not two near-identical icon
              // variants: travel_explore and travel_explore_outlined look the
              // same at AppBar size, so the toggle appeared not to respond.
              IconButton(
                tooltip: _controller.webSearch == true
                    ? 'Web search: on'
                    : 'Web search: off',
                isSelected: _controller.webSearch == true,
                selectedIcon: const Icon(Icons.travel_explore),
                icon: const Icon(Icons.travel_explore_outlined),
                style: IconButton.styleFrom(
                  backgroundColor: _controller.webSearch == true
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  foregroundColor: _controller.webSearch == true
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                onPressed: _controller.isStreaming
                    ? null
                    : () => _controller.webSearch =
                        !(_controller.webSearch ?? false),
              ),
              PopupMenuButton<String>(
                tooltip: 'Model: ${_controller.model}',
                enabled: !_controller.isStreaming,
                initialValue: _controller.model,
                onSelected: (model) => _controller.model = model,
                itemBuilder: (context) => [
                  for (final model in kAvailableModels)
                    PopupMenuItem(value: model, child: Text(model)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_controller.model,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Translate the last reply to English',
                onPressed: _controller.isStreaming ? null : _translateLastReply,
                icon: const Icon(Icons.translate),
              ),
              // A refresh arrow reads as "retry", not "start over", and on
              // mobile a tooltip needs a long-press to appear at all.
              IconButton(
                tooltip: 'New conversation',
                onPressed: _controller.clear,
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ],
          ),
          body: ChatView(
            controller: _controller,
            // No url_launcher dependency in this package, so the example shows
            // the source rather than opening it.
            onCitationTap: (citation) => ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(citation.url))),
          ),
        ),
      );
}
