import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/models/models.dart';
import '../../core/models/options.dart';

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
    this.sendOptions,
    this.onSend,
    this.composerLeading,
    this.composerHeader,
    super.key,
  });

  /// The controller driving the transcript.
  ///
  /// This view deliberately does NOT surface [ChatController.downgradeNotice].
  /// The anonymous backend ignores the requested model on every turn, so the
  /// notice would fire constantly and drown the case it exists for — the
  /// silent cap, where a conversation quietly drops to a smaller model after
  /// roughly ten turns. The signal is still on the controller; surface it
  /// yourself if your app requests specific models and wants to know.
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

  /// Options applied to every turn sent from this view's composer.
  ///
  /// Build it with `controller.currentOptions.copyWith(...)`, never a bare
  /// `SendOptions(...)` literal — a literal silently resets `model` to its
  /// default and the turn goes out as `auto`.
  final SendOptions? sendOptions;

  /// Overrides what pressing send does.
  ///
  /// The default sends [text] through [controller] with [sendOptions]. Supply
  /// this when a turn needs something the view does not own — attachments the
  /// app picked, for instance — and clear that state here, since the view
  /// cannot know when it has been consumed. [sendOptions] is then yours to
  /// pass on or ignore.
  final ValueChanged<String>? onSend;

  /// Widget placed at the start of the composer row, e.g. an attach button.
  final Widget? composerLeading;

  /// Widget placed directly above the composer.
  ///
  /// For state that belongs to the message being written rather than to the
  /// transcript: chips for pending attachments, a quoted message, a warning.
  final Widget? composerHeader;

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
                if (controller.isWritingReply) const TypingIndicator(),
                if (composerHeader != null) composerHeader!,
                MessageComposer(
                  onSend: onSend ??
                      (text) => controller.send(text, options: sendOptions),
                  enabled: !controller.isStreaming,
                  leading: composerLeading,
                ),
              ],
            ),
          );
        },
      );
}
