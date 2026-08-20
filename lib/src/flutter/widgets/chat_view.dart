import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/models/models.dart';

import '../chat_controller.dart';
import 'chat_message_list.dart';
import 'message_composer.dart';
import 'typing_indicator.dart';

/// A complete chat screen over a [ChatController].
class ChatView extends StatelessWidget {
  /// Creates the view.
  const ChatView({
    required this.controller,
    this.onCitationTap,
    this.onStartNewConversation,
    super.key,
  });

  /// The controller driving the transcript.
  final ChatController controller;

  /// Called with the source the reader tapped. Wire it to url_launcher, or
  /// leave it null and the citations render as plain, non-interactive chips —
  /// this package deliberately ships no URL-opening dependency.
  final ValueChanged<Citation>? onCitationTap;

  /// Offered as an action when the anonymous quota is exhausted.
  ///
  /// Rotating to a fresh device id clears the hourly cap immediately, and
  /// starting a new conversation is what does that — so this is the one
  /// remedy that actually works, not a generic "try again".
  final VoidCallback? onStartNewConversation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          // SafeArea, not a bare Column: without it the composer renders behind
          // the system navigation bar on a gesture-nav device and the send
          // button is unreachable. Under an AppBar the top inset is already
          // consumed, so keeping top:true costs nothing and covers the case
          // where a consumer uses ChatView without one.
          return SafeArea(
            child: Column(
              children: [
                if (controller.downgradeNotice != null)
                  MaterialBanner(
                    backgroundColor: scheme.tertiaryContainer,
                    content: Text(controller.downgradeNotice!),
                    actions: const [SizedBox.shrink()],
                  ),
                if (controller.error case final QuotaExceededException _)
                  MaterialBanner(
                    backgroundColor: scheme.tertiaryContainer,
                    content: const Text(
                      'This device has hit the anonymous hourly limit. '
                      'Starting a new conversation switches to a fresh device '
                      'and clears it right away.',
                    ),
                    actions: [
                      if (onStartNewConversation != null)
                        TextButton(
                          onPressed: onStartNewConversation,
                          child: const Text('New conversation'),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  )
                else if (controller.error != null)
                  MaterialBanner(
                    backgroundColor: scheme.errorContainer,
                    content: Text(controller.error!.message),
                    actions: const [SizedBox.shrink()],
                  ),
                Expanded(
                  child: ChatMessageList(
                    messages: controller.messages,
                    onCitationTap: onCitationTap,
                  ),
                ),
                if (controller.isStreaming) const TypingIndicator(),
                MessageComposer(
                  onSend: controller.send,
                  enabled: !controller.isStreaming,
                ),
              ],
            ),
          );
        },
      );
}
