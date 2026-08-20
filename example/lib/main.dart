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
  final ChatController _controller = ChatController(
    systemPrompt: 'Answer briefly.',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              IconButton(
                tooltip: _controller.webSearch == true
                    ? 'Web search: on'
                    : 'Web search: off',
                icon: Icon(_controller.webSearch == true
                    ? Icons.travel_explore
                    : Icons.travel_explore_outlined),
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
                tooltip: 'New conversation',
                onPressed: _controller.clear,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ChatView(controller: _controller),
        ),
      );
}
