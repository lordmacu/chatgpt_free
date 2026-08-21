# chatgpt_free

ChatGPT in Flutter with no API key and no account.

> **Unofficial and unaffiliated.** This package talks to an undocumented
> endpoint of the ChatGPT Android app. It is not affiliated with, endorsed
> by, or supported by OpenAI, and the endpoint can change or disappear
> without notice. Use it for prototypes and personal projects, not for
> anything you need to keep working.

## What it looks like

Every screenshot below is the app in `example/`, running against the real
anonymous endpoint — no account, no API key, no proxy in between.

### Chat

| Streaming reply | Web search, with sources | Conversations |
| --- | --- | --- |
| ![A streamed reply in the chat tab](doc/screenshots/chat.png) | ![A reply with citation chips under it](doc/screenshots/web-search.png) | ![A drawer listing three conversations by their backend-generated titles](doc/screenshots/conversations.png) |
| `ChatController` plus `ChatView`. | Citations arrive as `CitationsReceived`; tapping one is the app's call. | The titles are the backend's own, and they ride the reply stream — no extra request. |

### Attachments, JSON and Canvas

| Pending attachment | The model reads it | JSON mode |
| --- | --- | --- |
| ![A chip above the composer reading report.txt, 102 chars](doc/screenshots/attachments-pending.png) | ![A reply summarising the attached report](doc/screenshots/attachments.png) | ![A reply that is a raw JSON object](doc/screenshots/json-mode.png) |
| The app picks the file; the package takes no platform dependency for it. | Attachment text is inlined into the prompt — see [Attachments](#attachments-and-what-the-anonymous-backend-really-does-with-files) for why that is the only thing that works. | A prompt instruction, not an API flag. Turning it off sends an explicit retraction. |

| Canvas | Quota |
| --- | --- |
| ![A long document rendered as a canvas reply](doc/screenshots/canvas.png) | ![A sheet listing file_upload, paste_text_to_file and dictation with counts and reset times](doc/screenshots/limits.png) |
| Long-form documents come back as a `CanvasDocument`, markers stripped. | `Limits.remaining` and `Limits.resetAfter`, read without spending a message. |

### Translation

| |
| --- |
| ![English text translated to Spanish, with a language picker](doc/screenshots/translate.png) |
| `client.translate()` hits a different endpoint and spends **no** chat message — it keeps working after the hourly cap has stopped the chat. |

### Function calling ([`tools.dart`](#function-calling-packagechatgpt_freetoolsdart))

| One request, two calls | A parameter nobody stated |
| --- | --- |
| ![Two get_weather calls, for Lima and Quito, each with a call id](doc/screenshots/tools.png) | ![send_email needs more: subject and body were never stated](doc/screenshots/tools-need-info.png) |
| The backend has no function calling; this is a separate stateless request that produces it anyway. | Asked for, not invented — an invented subject validates against the schema just as well as a real one. |

### Generated interfaces ([`ui_schema.dart`](#generated-interfaces-packagechatgpt_freeui_schemadart))

| |
| --- |
| ![A calculator built from the model's JSON, showing the result 15](doc/screenshots/develop.png) |
| Asked for "a simple calculator", the model described one in JSON and this rendered it as real widgets. The 15 on the display is 7 + 8, computed by the arithmetic parser — nothing generated is executed. |

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

`Limits.remaining` says how much is left; `Limits.resetAfter` says when it
comes back, keyed the same way and in UTC. Zero remaining is not something
an app can act on by itself:

```dart
final limits = await session.limits();
final left = limits.remaining['file_upload'];        // 0
final back = limits.resetAfter['file_upload'];       // 2026-08-22T00:05:08Z
```

## Titles

The backend names each conversation itself and sends the name down the reply
stream, a beat after the last text delta — as a `ConversationTitled` event,
and on `session.title` / `ChatController.title` once it lands. A list of
conversations can label itself the moment the first answer arrives, with no
extra request:

```dart
await controller.send('¿Cuál es la capital de Mongolia?');
print(controller.title); // Buscar capital de Mongolia
```

The backend sometimes refines its first guess and sends a second title for
the same turn; the last one is the one it kept.

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

## Attachments, and what the anonymous backend really does with files

`session.send(text, attachments: [...])` takes `TextAttachment`s, and their
text is inlined into the prompt. That is not a shortcut around a missing
upload — it is the only thing that works. The anonymous backend does expose
`POST /files`: it answers 200 with a signed URL and the blob upload
succeeds, but finalising it (`POST /files/{id}/uploaded`) answers **401**,
the file never becomes readable, and the attempt still spends one of the
three uploads allowed per 24 hours. Inline text costs nothing from that
quota and the model actually reads it.

Reading a file needs a platform plugin, and this package has none, so
picking one is the app's job. `ChatView` provides the seams:

```dart
ChatView(
  controller: controller,
  // Attachments are yours to clear once spent; the view cannot know when.
  onSend: (text) async {
    final pending = List.of(_pending);
    setState(_pending.clear);
    await controller.send(text, attachments: pending);
  },
  composerLeading: IconButton(onPressed: _pick, icon: Icon(Icons.attach_file)),
  composerHeader: _pending.isEmpty ? null : _AttachmentChips(_pending),
)
```

The `example/` app does exactly this with `file_picker`, and refuses a file
that is not valid UTF-8 rather than inlining binary into the prompt.

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

## Function calling (`package:chatgpt_free/tools.dart`)

The backend has no function calling. This produces it anyway — the way JSON
mode is produced, by prompt — but through a dedicated, stateless request
rather than the conversation itself.

That separation is the design, not an implementation detail. Measured
anonymously: with the manifest in a live conversation's system prompt,
"weather in Lima and Quito" produced a usable envelope **0 times out of 5**
— the model answered from its own web search instead, and turning search
off did not reliably stop it. With the manifest in the user turn of a
throwaway session, the same request went **4 for 4**, and 25 of 28 over a
wider battery, with no false positives on 8 prompts that needed no function
at all.

So an extraction is not part of a conversation and cannot see one. Feed it
the request, run the calls yourself, and send the results into your chat
session as ordinary text.

```dart
import 'package:chatgpt_free/tools.dart';

final result = await ToolExtractor(client: client).extract(
  'What is the weather in Lima and in Quito?',
  functions: [
    FunctionTool.fromJson(mySchema), // OpenAI's tools shape, unchanged
  ],
);

switch (result) {
  case ToolCallsExtracted(:final calls):
    for (final call in calls) await run(call.name, call.arguments);
  case ToolInfoNeeded(:final missing):
    ask('I still need: ${missing.join(', ')}');
  case NoToolCall():
    await session.send(request);
}
```

`ToolInfoNeeded` is why this is worth more than a prompt you write yourself:
asked to send an email with no subject and no body, the model invents both,
and the invention validates cleanly against the schema. A wrong call that
looks exactly like a right one is the worst outcome available, so a missing
**required** parameter is reported instead of guessed.

One upstream message per extraction — the same anonymous allowance ordinary
chat spends. A second is spent only when the first reply was unusable
(measured at about 1 in 30), or when you pass `verify: true`. Verification
exists for the one real failure mode: a request packing about six conditions
loses one, and the result still validates, so no amount of schema checking
finds it. Re-reading the original request recovered the dropped filter in
measurement. Worth it for dense requests, wasteful for "the weather in
Bogotá".

`ToolChoice.auto` lets the model decline; `ToolChoice.any` forbids
declining; `ToolChoice.function('name')` pins one. Arguments are checked
against the declared JSON Schema — nested objects, arrays and enums
included — and a call that fails the check is sent back for repair before
you ever see it.

## Generated interfaces (`package:chatgpt_free/ui_schema.dart`)

A proof of concept, kept in its own library so it never reaches an app that
only wants the chat client. It asks the model for a screen described as
JSON, and renders that JSON as real widgets.

The vocabulary is deliberately tiny — eight node types and five actions —
because the point is to find out how well a model describes an interface,
not to be a UI framework. `kUiSchemaInstructions` is the prompt, and it
documents exactly what `UiSpec` parses: anything outside the vocabulary is
a `ProtocolException` rather than a guess, so a half-understood screen
refuses to render instead of rendering wrong.

```dart
import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/ui_schema.dart';

// A fresh session per attempt: the instructions are a prompt, so reusing a
// conversation would stack them turn after turn.
final session = ChatGptClient().newSession();
final reply = await session.sendJson(
  '$kUiSchemaInstructions\n\nuna calculadora simple',
);

// Renders as widgets, and runs its own actions.
Widget build(BuildContext context) => JsonUiView(spec: UiSpec.fromJson(reply));
```

Nothing generated is executed. State lives in `JsonUiView`, actions only
read and write that map, and the sole thing evaluated is the arithmetic
inside a `calc` action — by a hand-written parser that understands
`+ - * /`, parentheses and decimals, and nothing else.

| Node types | Actions |
| --- | --- |
| `column`, `row`, `grid`, `container`, `spacer`, `text`, `button`, `textField` | `set`, `append`, `clear`, `backspace`, `calc` |

The `Develop` tab in `example/` is this end to end: type what you want,
and the interface it builds is on screen and working.

## License

MIT — see [LICENSE](LICENSE).
