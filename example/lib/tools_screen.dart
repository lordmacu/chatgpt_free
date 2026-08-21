import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/tools.dart';
import 'package:flutter/material.dart';

/// Functions this demo pretends to own.
///
/// Real schemas, fake implementations: the point is what the model decides to
/// call and with what arguments, not what the functions do.
const List<FunctionTool> kDemoFunctions = [
  FunctionTool(
    name: 'get_weather',
    description: 'Current weather conditions for one city',
    parameters: {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'description': 'City name'},
        'units': {
          'type': 'string',
          'enum': ['celsius', 'fahrenheit'],
        },
      },
      'required': ['city'],
    },
  ),
  FunctionTool(
    name: 'send_email',
    description: 'Send an email to one recipient',
    parameters: {
      'type': 'object',
      'properties': {
        'to': {'type': 'string'},
        'subject': {'type': 'string'},
        'body': {'type': 'string'},
      },
      'required': ['to', 'subject', 'body'],
    },
  ),
  FunctionTool(
    name: 'set_timer',
    description: 'Start a countdown timer',
    parameters: {
      'type': 'object',
      'properties': {
        'minutes': {'type': 'integer'},
        'label': {'type': 'string'},
      },
      'required': ['minutes'],
    },
  ),
  FunctionTool(
    name: 'search_flights',
    description: 'Find flights between two airports on a date',
    parameters: {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': 'IATA code'},
        'to': {'type': 'string', 'description': 'IATA code'},
        'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
        'nonstop': {'type': 'boolean'},
      },
      'required': ['from', 'to', 'date'],
    },
  ),
];

/// A few requests worth trying, including the ones that should NOT call.
const List<String> kSamples = [
  'What is the weather in Lima and in Quito?',
  'Write me a haiku about the sea',
  'Send an email to ana@example.com',
  'Set a 10 minute timer for the pasta',
  'Nonstop flights BOG to MEX on 2026-09-14',
];

/// The tools tab: a request in, function calls out.
class ToolsScreen extends StatefulWidget {
  /// Creates the screen.
  const ToolsScreen({required this.client, super.key});

  /// Shared with the other tabs; the home screen owns and closes it.
  final ChatGptClient client;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final TextEditingController _prompt =
      TextEditingController(text: kSamples.first);

  ToolExtraction? _result;
  String? _error;
  bool _busy = false;
  bool _verify = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final request = _prompt.text.trim();
    if (request.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await ToolExtractor(client: widget.client).extract(
        request,
        functions: kDemoFunctions,
        verify: _verify,
      );
      if (mounted) setState(() => _result = result);
    } on ChatGptException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Request',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _run(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kSamples.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => ActionChip(
                      label: Text(kSamples[i], overflow: TextOverflow.ellipsis),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _prompt.text = kSamples[i]),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _run,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow, size: 18),
                        label: Text(_busy ? 'Extracting…' : 'Extract calls'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Off by default: it spends a second message, and only
                    // earns it on a request packing several conditions.
                    FilterChip(
                      label: const Text('verify'),
                      selected: _verify,
                      onSelected:
                          _busy ? null : (v) => setState(() => _verify = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(scheme)),
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(error, style: TextStyle(color: scheme.error)),
      );
    }

    final result = _result;
    if (result == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The backend has no function calling. This asks for one anyway, '
            'in a separate stateless request, and shows exactly what came '
            'back.\n\n'
            'Four functions are declared: weather, email, timer and flights.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Summary(result: result),
        const SizedBox(height: 8),
        switch (result) {
          ToolCallsExtracted(:final calls) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final call in calls) _CallCard(call: call)],
            ),
          ToolInfoNeeded(:final function, :final missing) => Card(
              color: scheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text('$function needs more'),
                // The whole reason this branch exists: invented values
                // validate against the schema just as well as real ones.
                subtitle: Text(
                  'Never stated in the request: ${missing.join(', ')}.\n'
                  'Asked for instead of invented.',
                ),
              ),
            ),
          NoToolCall(:final errors) => Card(
              child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('No function fits'),
                subtitle: Text(errors.isEmpty
                    ? 'Answer this one as ordinary chat.'
                    : errors.join('\n')),
              ),
            ),
        },
        if (result.raw.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Raw reply'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [SelectableText(result.raw)],
          ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final ToolExtraction result;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          // Messages are the honest cost unit: they come out of the same
          // anonymous hourly allowance as ordinary chat.
          Chip(
            avatar: const Icon(Icons.bolt_outlined, size: 16),
            label: Text('${result.requests} '
                '${result.requests == 1 ? 'message' : 'messages'}'),
          ),
          for (final note in result.notes)
            Chip(
              avatar: const Icon(Icons.info_outline, size: 16),
              label: Text(note),
            ),
        ],
      );
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.call});

  final ToolCall call;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.code, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      call.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final argument in call.arguments.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: '${argument.key}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: '${argument.value}'),
                  ])),
                ),
              if (call.arguments.isEmpty)
                const Text('no arguments',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 6),
              Text(
                call.id,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
}
