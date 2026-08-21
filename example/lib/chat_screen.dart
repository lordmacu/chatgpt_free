import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// The backend's own title if it has named this conversation, else the
  /// first user turn.
  ///
  /// The title arrives on the reply stream, so this becomes the real one a
  /// beat after the first answer — without fetching the conversation back.
  String get title {
    final fromServer = controller.title;
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
  bool _jsonMode = false;
  bool _canvas = false;

  @override
  void initState() {
    super.initState();
    _conversations.add(_newConversation());
  }

  Future<void> _showLimits() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final limits = await _controller.limits();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Anonymous quota'),
                subtitle: Text('Reported by the backend for this device.'),
              ),
              for (final e in limits.remaining.entries)
                ListTile(
                  dense: true,
                  title: Text(e.key),
                  subtitle: _resetLabel(limits.resetAfter[e.key]),
                  trailing: Text('${e.value}'),
                ),
              if (limits.cappedModels.isNotEmpty)
                ListTile(
                  dense: true,
                  title: const Text('Capped models'),
                  subtitle: Text(limits.cappedModels.join(', ')),
                ),
              if (limits.blockedFeatures.isNotEmpty)
                ListTile(
                  dense: true,
                  title: const Text('Blocked'),
                  subtitle: Text(limits.blockedFeatures.join(', ')),
                ),
            ],
          ),
        ),
      );
    } on ChatGptException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// "Back in 3 h 40 m", or nothing when the backend did not say.
  ///
  /// A remaining count alone is not actionable once it reaches zero — this is
  /// the half that tells the user when to come back.
  Widget? _resetLabel(DateTime? reset) {
    if (reset == null) return null;
    final left = reset.difference(DateTime.now().toUtc());
    if (left.isNegative) return const Text('available now');
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    return Text(
        hours > 0 ? 'back in ${hours}h ${minutes}m' : 'back in ${minutes}m');
  }

  Conversation _newConversation() {
    final controller = ChatController(
      client: widget.client,
      systemPrompt: 'Answer briefly.',
      // Visible in `adb logcat`. The gap between "reply complete" and "turn
      // closed" is the backend generating the conversation title, not the
      // package being slow.
      onLog: debugPrint,
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

  /// Opens a cited source in the browser.
  ///
  /// url_launcher is a dependency of THIS APP, not of the package: a widget
  /// library should not decide how its consumer opens links, which is why
  /// [ChatView.onCitationTap] is a callback.
  Future<void> _openSource(BuildContext context, Citation citation) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(citation.url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open ${citation.url}')),
      );
    }
  }

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
    await _conversations[index].controller.loadHistory();
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
            // No title: six actions plus the drawer button leave no room, and
            // a truncated "cha…" is worse than none.
            titleSpacing: 0,
            actions: [
              _ToggleAction(
                on: _controller.webSearch == true,
                icon: Icons.travel_explore_outlined,
                onIcon: Icons.travel_explore,
                label: 'Web search',
                onPressed: _controller.isStreaming
                    ? null
                    : () => _controller.webSearch =
                        !(_controller.webSearch ?? false),
              ),
              _ToggleAction(
                on: _jsonMode,
                icon: Icons.data_object_outlined,
                onIcon: Icons.data_object,
                label: 'JSON mode',
                onPressed: _controller.isStreaming
                    ? null
                    : () => setState(() => _jsonMode = !_jsonMode),
              ),
              _ToggleAction(
                on: _canvas,
                icon: Icons.article_outlined,
                onIcon: Icons.article,
                label: 'Canvas',
                onPressed: _controller.isStreaming
                    ? null
                    : () => setState(() => _canvas = !_canvas),
              ),
              IconButton(
                tooltip: 'Quota',
                onPressed: _showLimits,
                icon: const Icon(Icons.speed_outlined),
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
            // currentOptions.copyWith, never a bare SendOptions literal: a
            // literal would silently drop the picker's model back to auto.
            sendOptions: _controller.currentOptions
                .copyWith(jsonMode: _jsonMode, canvas: _canvas ? true : null),
            onCitationTap: (citation) => _openSource(context, citation),
            onStartNewConversation: _startConversation,
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

/// An AppBar toggle whose "on" state is unmistakable.
///
/// Material's outlined/filled icon pairs are nearly identical at AppBar size —
/// the web-search and JSON toggles both looked unresponsive until they got a
/// filled background. Every toggle here goes through this widget so the next
/// one cannot repeat that.
class _ToggleAction extends StatelessWidget {
  const _ToggleAction({
    required this.on,
    required this.icon,
    required this.onIcon,
    required this.label,
    required this.onPressed,
  });

  final bool on;
  final IconData icon;
  final IconData onIcon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '$label: ${on ? 'on' : 'off'}',
      isSelected: on,
      selectedIcon: Icon(onIcon),
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: on ? scheme.primaryContainer : null,
        foregroundColor: on ? scheme.onPrimaryContainer : null,
      ),
      onPressed: onPressed,
    );
  }
}
