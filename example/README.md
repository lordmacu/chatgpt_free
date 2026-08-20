# chatgpt_free example

A minimal chat screen built on `ChatController` and `ChatView` — no API key,
no account, just the anonymous ChatGPT backend.

Android, iOS and macOS scaffolding are all present (this package talks to
ChatGPT's Android endpoint, so Android is the platform that matters most —
macOS scaffolding was added first for local development convenience).

Run it with `flutter run` from this directory, with a device or emulator/
simulator attached — `flutter devices` lists what is available. To add
another platform (Linux, Windows, web), run `flutter create --platforms=<platform> .`
from this directory; that only adds the missing platform folder; it will not
touch `lib/main.dart`.
