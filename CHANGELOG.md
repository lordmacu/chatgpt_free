## 0.1.1

- Documented `translate` properly, and fixed two languages in the example that
  never worked: the endpoint rejects bare `pt` and `zh`, which need a region
  (`pt-BR`, `zh-CN`). The accepted codes are a fixed list, not a standard —
  `en-US` works and `en-GB` does not — so the README states the measured set
  and live tests keep it measured.
- `session.ask()` and `collectText()`: the reply as one `Future<String>`, for
  callers who do not want a stream. The wire is always SSE — the backend has
  no other mode — but consuming it incrementally was never required, and the
  fold these do is the one part of it that is easy to get wrong.
- README: "The library in one page" — the whole client surface up front, with
  every `SendOptions` field, every `ChatEvent`, every exception, and what each
  call costs from the anonymous allowance. The README used to open with a
  Flutter widget example, which is the wrong first thing for a library.
- README screenshots now use absolute URLs. pub.dev strips relative image
  links rather than resolving them against `repository`, so 0.1.0 rendered
  twelve alt texts in square brackets.
- Fixed the documented signature of `translate`: it takes `target:` and
  `source:`, not `targetLanguageCode:`.

## 0.1.0

- First release: anonymous chat with streaming, web search with citations,
  Canvas, JSON mode, text attachments, models and limits.
- Reports the backend's silent model downgrade as `ModelDowngraded`.
- Rotates the device id automatically when the hourly cap trips.
- Reports the backend's own conversation title as it arrives on the reply
  stream (`ConversationTitled`, `session.title`, `ChatController.title`).
- `Limits.resetAfter` says when each capped feature comes back.
- `ChatView`: `onSend`, `composerLeading` and `composerHeader`, so an app
  can attach files without the package taking a platform dependency.
- Flutter layer: `ChatController` plus themed widgets and `ChatView`.
- `package:chatgpt_free/tools.dart`: custom function calling, emulated
  through a stateless extraction request. Returns OpenAI-shaped calls,
  reports a missing required parameter instead of inventing one, and
  validates arguments against the declared JSON Schema.
- Tool-call detection reads every dialect a prompted model emits, gated on the
  declared functions; `ToolChoice.function(...)` is enforced by the parser, not
  only prompted; arguments are repaired against their schema losslessly.
- `ChatGptClient.newEphemeralSession()`, for work that must not persist a
  throwaway device id over the app's real one.
- Proof of concept: `package:chatgpt_free/ui_schema.dart`, a JSON vocabulary
  the model can use to describe a screen, and `JsonUiView` to render it.
