import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/ui_schema.dart';
import 'package:flutter/material.dart';

/// Developer mode: ask for an interface, get a running one.
///
/// A proof of concept. The model is handed [kUiSchemaInstructions] — the exact
/// vocabulary [UiSpec] parses, nothing aspirational — and its JSON reply is
/// rendered as real widgets by [JsonUiView]. Nothing is executed: the only
/// thing evaluated is the arithmetic inside a `calc` action.
class BuildScreen extends StatefulWidget {
  /// Creates the screen.
  const BuildScreen({required this.client, super.key});

  /// Shared with the other tabs; the home screen owns and closes it.
  final ChatGptClient client;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  final TextEditingController _prompt =
      TextEditingController(text: 'a simple calculator');

  UiSpec? _spec;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final ask = _prompt.text.trim();
    if (ask.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _spec = null;
    });

    // A fresh session per attempt: the instructions are a prompt, so reusing a
    // conversation would stack them turn after turn.
    final session = widget.client.newSession();
    try {
      final reply = await session.sendJson('$kUiSchemaInstructions\n\n$ask');
      if (!mounted) return;
      setState(() => _spec = UiSpec.fromJson(reply));
    } on ChatGptException catch (e) {
      if (!mounted) return;
      // Show what the model got wrong: with a generated interface, the error
      // IS the interesting result.
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = _spec;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _prompt,
                  decoration: const InputDecoration(
                    labelText: 'Describe an interface',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _generate(),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _generate,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_busy ? 'Generating…' : 'Generate'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch ((_error, spec)) {
              (final String message, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('The model produced something this renderer '
                          'refuses:'),
                      const SizedBox(height: 8),
                      SelectableText(message,
                          style: TextStyle(color: scheme.error)),
                    ],
                  ),
                ),
              (null, final UiSpec s) => SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (s.title != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Text(
                            s.title!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      JsonUiView(
                        spec: s,
                        onError: (e) => ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message))),
                      ),
                    ],
                  ),
                ),
              _ => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Ask for an interface and it will be built here.\n\n'
                      'This is a proof of concept: the model may only use a '
                      'small documented vocabulary, and anything outside it is '
                      'rejected rather than guessed at.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }
}
