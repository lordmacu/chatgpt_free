## 0.1.4

- `session.answer()` and `collectAnswer()`: everything a turn produced, in one
  `await` — the text, the citations, the search queries, the Canvas document,
  the generated title, the model that actually replied, the quota snapshot,
  and any device rotations it took. `ask()` returns the words; asking anything
  with `webSearch` and then wanting the sources used to mean going back to a
  stream for want of one field.
- `collectText()` now delegates to `collectAnswer()`, so the fold that
  `isReset` requires exists once in the package rather than twice.
- **Documented the real platform support.** pub.dev reports six platforms
  because that badge is inferred from imports, and this package imports
  nothing platform-specific. Web does not work and cannot: the endpoint sends
  no `Access-Control-Allow-Origin`, and its `Access-Control-Allow-Headers`
  permits only `content-type` where the protocol needs fourteen headers.

## 0.1.3

- Documentation only. The README now opens with code: everything the client
  does, in one block — ask, stream, web search with sources, JSON,
  attachments, translation, quota. It used to open with screenshots of the
  example app, which shows what was built with the library rather than how to
  use it. The block is compiled by `flutter analyze`, so the most-read snippet
  in the package cannot quietly stop working.

## 0.1.2

- **Fixed two languages in the example that never worked.** The translate
  endpoint rejects bare `pt` and `zh`; they need a region (`pt-BR`, `zh-CN`).
  Anyone picking Português or 中文 in the demo got HTTP 400, in 0.1.0 and
  0.1.1 alike.
- Documented `translate`. The accepted codes are a fixed list, not a standard
  — `fr` works bare and `pt` does not, `en-US` works and `en-GB` does not —
  so the README states the measured set, says the package ships no list of
  its own, and live tests keep the table from going stale. Also measured:
  `source` is decorative, empty text is a 400, and 4,000 characters go
  through in one call.
- `session.ask()` and `collectText()`: the reply as one `Future<String>`, for
  callers who do not want a stream. The wire is always SSE — the backend has
  no other mode, verified against `force_use_sse: false`, `stream: false` and
  `Accept: application/json` — but consuming it incrementally was never
  required, and the fold these do is the one part of it that is easy to get
  wrong.

## 0.1.1

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
