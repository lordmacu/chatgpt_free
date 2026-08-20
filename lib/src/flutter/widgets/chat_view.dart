import 'package:flutter/material.dart';

import '../chat_controller.dart';
import 'chat_message_list.dart';
import 'message_composer.dart';
import 'typing_indicator.dart';

/// A complete chat screen over a [ChatController].
class ChatView extends StatelessWidget {
  /// Creates the view.
  const ChatView({required this.controller, super.key});

  /// The controller driving the transcript.
  final ChatController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          return Column(
            children: [
              if (controller.downgradeNotice != null)
                MaterialBanner(
                  backgroundColor: scheme.tertiaryContainer,
                  content: Text(controller.downgradeNotice!),
                  actions: const [SizedBox.shrink()],
                ),
              if (controller.error != null)
                MaterialBanner(
                  backgroundColor: scheme.errorContainer,
                  content: Text(controller.error!.message),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(child: ChatMessageList(messages: controller.messages)),
              if (controller.isStreaming) const TypingIndicator(),
              MessageComposer(
                onSend: controller.send,
                enabled: !controller.isStreaming,
              ),
            ],
          );
        },
      );
}
