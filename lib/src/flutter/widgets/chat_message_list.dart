import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import 'message_bubble.dart';

/// A scrolling transcript that sticks to the newest message.
class ChatMessageList extends StatefulWidget {
  /// Creates the list.
  const ChatMessageList({required this.messages, super.key});

  /// Messages, oldest first.
  final List<ChatMessage> messages;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.messages.length,
        itemBuilder: (_, i) => MessageBubble(message: widget.messages[i]),
      );
}
