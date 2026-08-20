import 'package:flutter/material.dart';

/// The input row: a text field and a send button.
class MessageComposer extends StatefulWidget {
  /// Creates the composer.
  const MessageComposer({
    required this.onSend,
    this.enabled = true,
    this.hintText = 'Message…',
    super.key,
  });

  /// Called with the submitted text.
  final ValueChanged<String> onSend;

  /// Whether input is accepted.
  final bool enabled;

  /// Placeholder text.
  final String hintText;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();

  void _submit() {
    if (!widget.enabled) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.enabled ? _submit : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      );
}
