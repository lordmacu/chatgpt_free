# chatgpt_free

ChatGPT in Flutter with no API key and no account.

> **Unofficial and unaffiliated.** This package talks to an undocumented
> endpoint of the ChatGPT Android app. It is not affiliated with, endorsed
> by, or supported by OpenAI, and the endpoint can change or disappear
> without notice. Use it for prototypes and personal projects, not for
> anything you need to keep working.

## Install

```yaml
dependencies:
  chatgpt_free: ^0.1.0
```

## Quickstart

A full chat screen in ten lines, built on `ChatController` and `ChatView`:

```dart
import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = ChatController(systemPrompt: 'Answer briefly.');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: ChatView(controller: _controller));
}
```

`ChatController` owns a `ChatGptClient`, streams replies into its
`messages` list, and calls `notifyListeners()` as they arrive — `ChatView`
just renders whatever the controller currently has, including a typing
indicator, citation chips, and a banner when the backend downgrades the
model mid-conversation.

## Using the client directly

Skip Flutter entirely and drive the core client yourself. `ChatEvent` is a
sealed class, so a `switch` over it is exhaustive and the compiler will flag
any new event type you haven't handled.

```dart
import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/src/core/client.dart';

final client = ChatGptClient();
final session = client.newSession();

var buffer = '';
await for (final event
    in client.sendWithRotation(session, 'Explain recursion in one sentence.')) {
  switch (event) {
    case TextDelta(:final text, :final isReset):
      // Fold, never concatenate: isReset means the backend replaced or
      // truncated what it already streamed. Appending here would duplicate
      // text the backend just discarded.
      buffer = isReset ? text : buffer + text;
    case ModelDowngraded(:final requested, :final actual):
      print('Requested $requested, backend answered with $actual.');
    case QuotaRotated(:final reason):
      print('Hourly cap hit ($reason) — rotated device id and retried.');
    case TurnCompleted(:final actualModel):
      print('[$actualModel] $buffer');
    default:
      break;
  }
}

client.close();
```

The `isReset` fold above is not decorative — appending on every `TextDelta`
without checking it will silently duplicate text the first time the backend
edits a reply mid-stream. This shipped as a real bug once; the `switch`
above is the correct shape.

## Limits

There's no billing and no dashboard, so the anonymous quota is whatever the
Android app itself gets, and it is tighter than a paid account:

- **Per-model ceiling.** Roughly **10 messages on the top model
  (`gpt-5-6`)** before the backend silently downgrades you to
  `gpt-5-6-mini`. The HTTP response is still `200`, there's no error and no
  header announcing it — the only way to notice is that the model in the
  response changed. This package watches for exactly that and surfaces it
  as a `ModelDowngraded` event so your app can tell the user, instead of
  silently serving weaker replies.
- **Hourly ceiling.** Roughly **30 to 45 messages per device per hour**
  before a real `429`, whose body reads *"You've reached our limit of
  messages per hour."* That range is a range on purpose: it depends on
  what else has come from your IP address recently, not just your own
  message count. When it trips, `sendWithRotation` rotates to a fresh
  device id and retries the message once automatically — you'll see a
  `QuotaRotated` event, and the conversation continues (local history is
  replayed inline into the next prompt, since the server-side conversation
  state is tied to the old device id and is lost).

Anonymous sessions also carry: `file_upload` capped at 3 per 24 hours,
`dictation` capped at 1 per 7 days, `image_gen` blocked outright, and a
34,834-token context window. Call `client.limits()` to read the current
state of all of these without spending a message.

## What works anonymously

| Capability | Anonymous support |
| --- | --- |
| Streaming text replies | Yes |
| Web search with citations | Yes |
| Canvas documents | Yes |
| JSON mode | Yes |
| Text file attachments | Yes (plain text only — extract text yourself first) |
| Vision (image input) | No |
| `tool_calls` / function calling | No |
| `temperature`, `top_p`, `max_tokens` | No — the backend doesn't expose them; `SendOptions` only has what the Android app itself can set |
| Image generation | No — blocked outright for anonymous sessions |
| Translation, without spending a chat message | Yes — `client.translate()` |

## Persisting state across restarts

The package keeps no platform storage dependency of its own — it stores
only the device id and conversation id, through the small `ChatGptStore`
interface, so you can back it with whatever your app already uses
(`shared_preferences`, Hive, secure storage, ...):

```dart
import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsStore implements ChatGptStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

final client = ChatGptClient(store: SharedPrefsStore());
```

Without a store, state lives only as long as the process does — every
fresh launch starts a brand-new anonymous device.

## License

MIT — see [LICENSE](LICENSE).
