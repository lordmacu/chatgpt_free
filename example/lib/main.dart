import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter/material.dart';

import 'build_screen.dart';
import 'chat_screen.dart';
import 'translate_screen.dart';

void main() => runApp(const ExampleApp());

/// Model ids the anonymous backend actually serves, most to least capable.
const List<String> kAvailableModels = [
  'auto',
  'gpt-5-6',
  'gpt-5-5',
  'gpt-5-6-mini',
  'gpt-5-5-mini',
  'gpt-5-3-mini',
];

/// Demo app: chat and translation with no API key and no account.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'chatgpt_free',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B899)),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      );
}

/// Two tabs over one client.
///
/// Translation lives on its own tab rather than as a chat action because it
/// hits a different endpoint and spends no message from the anonymous quota —
/// it keeps working after the chat has hit its hourly cap, and it does not
/// need a conversation to exist first.
class HomeScreen extends StatefulWidget {
  /// Creates the home.
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // One client for both tabs: a session's quota and rotation state live in the
  // client, so handing each tab its own would double the device ids in play.
  final ChatGptClient _client = ChatGptClient();
  int _tab = 0;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        // IndexedStack, not a switch on _tab: it keeps the chat's transcript
        // and the translation's text alive while the other tab is on screen.
        body: IndexedStack(
          index: _tab,
          children: [
            TranslateScreen(client: _client),
            ChatScreen(client: _client),
            BuildScreen(client: _client),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.translate_outlined),
              selectedIcon: Icon(Icons.translate),
              label: 'Translate',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'Develop',
            ),
          ],
        ),
      );
}
