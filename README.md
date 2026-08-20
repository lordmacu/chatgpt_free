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

## Changing model and web search mid-conversation

`ChatController.model` and `.webSearch` are settable, not just
constructor arguments, and each setter calls `notifyListeners()` so a
picker or a switch bound to the controller rebuilds on its own:

```dart
DropdownButton<String>(
  value: controller.model,
  onChanged: controller.isStreaming
      ? null
      : (model) => controller.model = model!,
  items: [
    for (final m in ['auto', 'gpt-5-6', 'gpt-5-5', 'gpt-5-6-mini'])
      DropdownMenuItem(value: m, child: Text(m)),
  ],
);
```

Changing `model` mid-conversation does **not** start a new conversation —
the transcript and the session's `conversationId` both survive. Only
later turns pick up the new value; the backend accepts a different
`model` slug on a later turn of the same conversation.

Both setters **throw `StateError` if called while `controller.isStreaming`
is `true`.** A change made then could never reach the reply already
streaming in — its `SendOptions` were built and sent before the setter
call — so applying it would leave the controller's reported setting
disagreeing with what actually produced the text on screen. The fix is
the same one the snippet above already shows: disable the control
(`onChanged: controller.isStreaming ? null : ...`) instead of leaving it
live and catching the exception. Note that this is a plain `StateError`,
not a `ChatGptException` — a blanket `on ChatGptException catch (e) {
... }` around your UI code will not catch it, so guard the setter call
itself rather than relying on that catch block.

## Per-turn options: `SendOptions` and attachments

`ChatController.send()` takes the same per-turn `options` and
`attachments` that the core `ChatGptSession.send()` does, for the calls
where the controller's own `model`/`webSearch` settings aren't enough —
Canvas, JSON mode, `thinkingEffort`, `serviceTier`, or a one-off text
attachment.

**Precedence:** an explicit `options` argument is used exactly as given —
it is never merged field-by-field with `controller.model` /
`controller.webSearch`. Omit `options` (as every call before this
parameter existed still can) and the turn falls back to
`controller.currentOptions` — `SendOptions(model: controller.model,
webSearch: controller.webSearch)`, built fresh from the controller's
current settings at call time. Pass `options` and it is the whole story
for that turn; omit it and the controller's current settings are.

**This has a sharp edge: never build a per-turn override from a bare
`SendOptions(...)` literal.** `SendOptions.model` defaults to `'auto'`, so
```dart
// Wrong — silently sends model: 'auto', even if the picker shows gpt-5-6.
await controller.send('Turn this into a doc.',
    options: const SendOptions(canvas: true));
```
sends `'auto'` in place of whatever model your picker has selected — and
nothing tells you: `ModelDowngraded` compares the *requested* model
against the one that answered, and here the (wrong) request and the
answer both say `'auto'`, so it looks like a correct request rather than
a bug. This is the same class of silent model substitution the package
exists to expose in the backend — don't reintroduce it at this boundary.

Start from `controller.currentOptions` and `copyWith` instead, so only the
field you actually mean to change moves:

```dart
await controller.send(
  'Turn this into a doc.',
  options: controller.currentOptions.copyWith(canvas: true),
);

await controller.send(
  'Summarize the attached notes as JSON.',
  options: controller.currentOptions.copyWith(jsonMode: true),
  attachments: const [TextAttachment(name: 'notes.md', content: '...')],
);
```

`SendOptions.copyWith(...)` replaces only the fields you name and keeps
the rest — including `model` — exactly as they were. One caveat: for the
three nullable fields (`webSearch`, `tools`, `canvas`), `copyWith` can't
tell "leave unchanged" apart from "set to `null`" (both look like an
omitted argument), so it can never *clear* one of those back to `null` —
construct a fresh `SendOptions(...)` directly if you need that.

## Using the client directly

Skip Flutter entirely and drive the core client yourself. `ChatEvent` is a
sealed class, so a `switch` over it is exhaustive and the compiler will flag
any new event type you haven't handled.

```dart
import 'package:chatgpt_free/chatgpt_free.dart';

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
    case SearchStarted() ||
          CitationsReceived() ||
          GenuiWidgetEvent() ||
          CanvasDocument() ||
          ImageGenerated():
      break; // Not shown here — see the API docs for these event types.
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
(`shared_preferences`, Hive, secure storage, ...). Saving is automatic once
a store is attached, but resuming is not: `ChatGptClient.newSession()`
always starts a brand-new device, even with a store attached, so attaching
one never silently resumes a stranger's — or last run's own abandoned —
conversation. Call `ChatGptClient.restoreSession()` (or the lower-level
`ChatGptSession.restore(...)`) when you actually want that:

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
final session = await client.restoreSession();
print(session.deviceId); // same id as last run, once one was ever saved
```

Without a store — or without calling `restoreSession()` — state lives only
as long as the process does: every fresh launch starts a brand-new
anonymous device.

## License

MIT — see [LICENSE](LICENSE).
