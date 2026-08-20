import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('chatgpt_free'),
          actions: [
            IconButton(
              tooltip: 'New conversation',
              onPressed: _controller.clear,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ChatView(controller: _controller),
      );
}
