## 0.1.0

- First release: anonymous chat with streaming, web search with citations,
  Canvas, JSON mode, text attachments, models and limits.
- Reports the backend's silent model downgrade as `ModelDowngraded`.
- Rotates the device id automatically when the hourly cap trips.
- Reports the backend's own conversation title as it arrives on the reply
  stream (`ConversationTitled`, `session.title`, `ChatController.title`).
- `Limits.resetAfter` says when each capped feature comes back.
- Flutter layer: `ChatController` plus themed widgets and `ChatView`.
- Proof of concept: `package:chatgpt_free/ui_schema.dart`, a JSON vocabulary
  the model can use to describe a screen, and `JsonUiView` to render it.
