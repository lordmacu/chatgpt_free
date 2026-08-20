// Imports ONLY the public library — never `src/...` — because this file's
// whole point is to prove every type the README shows off the public
// surface is actually reachable from `package:chatgpt_free/chatgpt_free.dart`
// alone. If this file fails to compile, the README's snippets can't
// possibly compile either (Fix round 1, Finding 1: `ChatGptClient` and
// `ChatGptSession` were missing from the library's exports).
import 'dart:async';

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

// Final review, Blocker 1: `ChatGptClient({Transport? transport})` and
// `ChatGptSession({Transport? transport})` are public constructors
// parameterised on `Transport`, but `src/core/transport.dart` was never
// exported from the public library. A consumer following the README's own
// advice — "swap the transport out in tests" — writing exactly this
// `implements Transport` below, importing only `package:chatgpt_free/
// chatgpt_free.dart`, got `implements_non_class` at compile time. Defining
// it here, in a file that imports only the public library, is what makes a
// regression in the export list fail this file's compilation rather than
// slipping through unnoticed — the same mechanism the file already relies on
// for `ChatGptClient`/`ChatGptSession` above.
class _StubTransport implements Transport {
  @override
  Future<Stream<List<int>>> stream(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async =>
      const Stream<List<int>>.empty();

  @override
  Future<String> get(String path, {required String deviceId}) async => '{}';

  @override
  Future<String> post(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async =>
      '{}';

  @override
  void close() {}
}

void main() {
  test(
      'every type appearing in a public constructor or method signature is '
      'reachable from the public library alone (Final review, Blocker 1)',
      () {
    // Constructing for real — not just naming the type — is what forces a
    // compile error if the export is missing.
    final transport = _StubTransport();
    final client = ChatGptClient(transport: transport, store: InMemoryStore());
    final session =
        ChatGptSession(transport: transport, store: InMemoryStore());

    expect(client, isA<ChatGptClient>());
    expect(session, isA<ChatGptSession>());
    expect(transport, isA<Transport>());

    client.close();
    session.close();
  });

  test('HttpTransport, the concrete Transport this package ships, is also '
      'reachable from the public library alone (Final review, Blocker 1)',
      () {
    final transport = HttpTransport();
    expect(transport, isA<Transport>());
    transport.close();
  });

  test('ChatGptClient and ChatGptSession are reachable from the public '
      'library alone', () {
    // Constructing for real (not just referencing the type) is what forces
    // a compile error if the export is missing — a bare type annotation can
    // sometimes be satisfied by an unrelated import left over elsewhere in
    // the file, a live constructor call cannot.
    final client = ChatGptClient();
    final session = client.newSession(systemPrompt: 'Answer briefly.');

    expect(client, isA<ChatGptClient>());
    expect(session, isA<ChatGptSession>());

    client.close();
  });

  test('every other type the README references resolves from the public '
      'library too', () {
    // One line per README-referenced type. If any of these were only
    // reachable via `src/...`, this file would fail to compile.
    final ChatGptStore store = InMemoryStore();
    const SendOptions options = SendOptions();
    const TextAttachment attachment = TextAttachment(name: 'a.txt', content: 'x');
    const ChatEvent event = TextDelta('hi');
    const ModelDowngraded downgraded =
        ModelDowngraded(requested: 'gpt-5-6', actual: 'gpt-5-6-mini');
    const QuotaRotated rotated = QuotaRotated('hourly cap');
    const TurnCompleted completed = TurnCompleted(actualModel: 'gpt-5-6');
    const ChatMessage message = ChatMessage(role: 'user', text: 'hi');

    expect(store, isNotNull);
    expect(options, isNotNull);
    expect(attachment, isNotNull);
    expect(event, isA<TextDelta>());
    expect(downgraded, isNotNull);
    expect(rotated, isNotNull);
    expect(completed, isNotNull);
    expect(message, isNotNull);
  });
}
