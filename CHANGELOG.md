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
- `ChatGptClient.newEphemeralSession()`, for work that must not persist a
  throwaway device id over the app's real one.
- Proof of concept: `package:chatgpt_free/ui_schema.dart`, a JSON vocabulary
  the model can use to describe a screen, and `JsonUiView` to render it.
