import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';

import 'main.dart' show kAvailableModels;

/// One conversation in the drawer.
///
/// The LIST is local, because anonymous conversations cannot be listed:
/// `/conversations` answers 200 with an empty page. The CONTENT is not — an
/// anonymous conversation can be fetched by id from the device that created
/// it (another device gets 404), so selecting one here re-reads its real
/// transcript and the backend's own title. Each conversation is a separate
/// [ChatController], and they share the client, its transport and its quota.
class Conversation {
  /// Creates a conversation around [controller].
  Conversation(this.controller);

  /// The controller driving this conversation.
  final ChatController controller;

  /// Title the backend generated, once the conversation has been fetched.
  String? serverTitle;

  /// The backend's title when we have fetched it, else the first user turn.
  String get title {
    final fromServer = serverTitle;
    if (fromServer != null && fromServer.trim().isNotEmpty) return fromServer;
    for (final m in controller.messages) {
      if (m.role == 'user' && m.text.trim().isNotEmpty) {
        final t = m.text.trim().replaceAll('\n', ' ');
        return t.length <= 40 ? t : '${t.substring(0, 40)}…';
      }
    }
    return 'New chat';
  }
}

/// The chat tab: the package's Flutter layer, plus a drawer of local
/// conversations.
class ChatScreen extends StatefulWidget {
  /// Creates the screen.
  const ChatScreen({required this.client, super.key});

  /// Shared with the translate tab; the home screen owns and closes it.
  final ChatGptClient client;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Conversation> _conversations = [];
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _conversations.add(_newConversation());
  }

  Conversation _newConversation() {
    final controller = ChatController(
      client: widget.client,
      systemPrompt: 'Answer briefly.',
    );
    // Rebuild the drawer's titles as turns land.
    controller.addListener(_onControllerChanged);
    return Conversation(controller);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _conversations) {
      c.controller
        ..removeListener(_onControllerChanged)
        ..dispose();
    }
    super.dispose();
  }

  ChatController get _controller => _conversations[_active].controller;

  void _startConversation() {
    setState(() {
      _conversations.add(_newConversation());
      _active = _conversations.length - 1;
    });
  }

  Future<void> _select(int index) async {
    setState(() => _active = index);
    // Pull the transcript back from the backend rather than trusting the local
    // copy: an anonymous conversation is readable by id from the device that
    // created it, which is what makes this drawer more than a UI illusion.
    final title = await _conversations[index].controller.loadHistory();
    if (title != null && mounted) {
      setState(() => _conversations[index].serverTitle = title);
    }
  }

  void _delete(int index) {
    final removed = _conversations[index];
    setState(() {
      _conversations.removeAt(index);
      if (_conversations.isEmpty) {
        _conversations.add(_newConversation());
        _active = 0;
      } else if (_active >= _conversations.length) {
        _active = _conversations.length - 1;
      } else if (index < _active) {
        _active -= 1;
      }
    });
    removed.controller
      ..removeListener(_onControllerChanged)
      ..dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        // The AppBar reads controller state directly, so it has to rebuild with
        // it: the model picker and the web-search toggle grey themselves out
        // while a turn streams, because ChatController.model/webSearch throw
        // StateError if set at that point.
        animation: _controller,
        builder: (context, _) => Scaffold(
          drawer: _ConversationsDrawer(
            conversations: _conversations,
            active: _active,
            onSelect: (i) {
              Navigator.pop(context);
              _select(i);
            },
            onNew: () {
              Navigator.pop(context);
              _startConversation();
            },
            onDelete: _delete,
          ),
          appBar: AppBar(
            title: const Text('chatgpt_free'),
            actions: [
              IconButton(
                tooltip: _controller.webSearch == true
                    ? 'Web search: on'
                    : 'Web search: off',
                isSelected: _controller.webSearch == true,
                selectedIcon: const Icon(Icons.travel_explore),
                icon: const Icon(Icons.travel_explore_outlined),
                style: IconButton.styleFrom(
                  backgroundColor: _controller.webSearch == true
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  foregroundColor: _controller.webSearch == true
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
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
                onPressed: _startConversation,
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ],
          ),
          body: ChatView(
            controller: _controller,
            // This package ships no url_launcher dependency, so the example
            // shows the source rather than opening it.
            onCitationTap: (citation) => ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(citation.url))),
          ),
        ),
      );
}

class _ConversationsDrawer extends StatelessWidget {
  const _ConversationsDrawer({
    required this.conversations,
    required this.active,
    required this.onSelect,
    required this.onNew,
    required this.onDelete,
  });

  final List<Conversation> conversations;
  final int active;
  final ValueChanged<int> onSelect;
  final VoidCallback onNew;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) => Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New chat'),
                onTap: onNew,
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, i) => ListTile(
                    selected: i == active,
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      conversations[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDelete(i),
                    ),
                    onTap: () => onSelect(i),
                  ),
                ),
              ),
              const Divider(height: 1),
              // Say plainly why this list is local: a reader of the example
              // should not assume the package can fetch server-side history.
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'The list is local: anonymous conversations cannot be '
                  'listed. Their content is real — selecting one re-reads it '
                  'from the backend by id.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
}
