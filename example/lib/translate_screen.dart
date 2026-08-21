import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A short, readable set of languages. The backend accepts any code — this
/// list stays small because the example is documentation, not a product.
/// Every code here was checked against the live endpoint, because the
/// backend's list is arbitrary and cannot be derived: `fr` and `de` work
/// bare, but `pt` and `zh` are rejected and need a region, `en-US` works
/// while `en-GB` does not, and `he`, `uk`, `el` and `da` do not exist at all.
/// `pt` and `zh` shipped here and always failed.
const Map<String, String> kLanguages = {
  'es': 'Español',
  'en': 'English',
  'pt-BR': 'Português',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'ja': '日本語',
  'zh-CN': '中文',
  'ko': '한국어',
  'ru': 'Русский',
  'ar': 'العربية',
  'hi': 'हिन्दी',
};

/// Translation, on its own tab.
///
/// Worth separating from the chat: `translate()` hits a different endpoint and
/// **spends no message from the anonymous quota**, so it keeps working after
/// the chat has hit its hourly cap, and it needs no conversation to exist.
class TranslateScreen extends StatefulWidget {
  /// Creates the screen.
  const TranslateScreen({required this.client, super.key});

  /// Shared with the chat tab; the home screen owns and closes it.
  final ChatGptClient client;

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// null means "detect", which is what omitting `source` on the API does.
  String? _source;
  String _target = 'en';

  String _output = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _swap() {
    if (_source == null) return;
    setState(() {
      final oldSource = _source!;
      _source = _target;
      _target = oldSource;
      final text = _output;
      _output = '';
      _input.text = text;
    });
  }

  Future<void> _translate() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    _focus.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await widget.client.translate(text, target: _target, source: _source);
      if (!mounted) return;
      setState(() => _output = result);
    } on ChatGptException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick({required bool forSource}) async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (forSource)
              ListTile(
                title: const Text('Detect language'),
                trailing: _source == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, '__detect__'),
              ),
            for (final e in kLanguages.entries)
              ListTile(
                title: Text(e.value),
                trailing: (forSource ? _source : _target) == e.key
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      if (forSource) {
        _source = chosen == '__detect__' ? null : chosen;
      } else {
        _target = chosen;
      }
    });
  }

  String get _sourceLabel =>
      _source == null ? 'Detect' : kLanguages[_source] ?? _source!;
  String get _targetLabel => kLanguages[_target] ?? _target;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source pane: the language above the text, the way a translator app
          // reads, rather than a form with labelled fields.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_sourceLabel,
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                TextField(
                  controller: _input,
                  focusNode: _focus,
                  maxLines: 4,
                  minLines: 1,
                  style: text.headlineSmall,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _translate(),
                  decoration: const InputDecoration(
                    hintText: 'Enter text',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
                Row(
                  children: [
                    if (_input.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() {
                          _input.clear();
                          _output = '';
                          _error = null;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _busy || _input.text.trim().isEmpty
                          ? null
                          : _translate,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward, size: 18),
                      label: Text(_busy ? 'Translating…' : 'Translate'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // The language bar sits between the two panes, like the reference.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              color: scheme.surfaceContainerHighest,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => _pick(forSource: true),
                        child:
                            Text(_sourceLabel, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    IconButton(
                      tooltip: _source == null
                          ? 'Pick a source language to swap'
                          : 'Swap',
                      onPressed: _source == null ? null : _swap,
                      icon: const Icon(Icons.swap_horiz),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _pick(forSource: false),
                        child:
                            Text(_targetLabel, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Result pane.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: _error != null
                  ? Text(_error!, style: TextStyle(color: scheme.error))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_targetLabel,
                            style: text.labelLarge
                                ?.copyWith(color: scheme.primary)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _output,
                              style: text.headlineSmall
                                  ?.copyWith(color: scheme.primary),
                            ),
                          ),
                        ),
                        if (_output.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              tooltip: 'Copy',
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: _output));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied')),
                                );
                              },
                              icon: const Icon(Icons.copy_outlined),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
