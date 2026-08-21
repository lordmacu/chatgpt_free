import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test('ask returns the finished reply, with no stream to consume', () async {
    final client = ChatGptClient(transport: FakeTransport());
    final session = client.newSession();

    final reply = await session.ask('Di hola mundo');

    expect(reply.trim(), 'hola mundo');
    client.close();
  });

  test('collectText folds on isReset instead of appending', () async {
    // The whole reason this is a function and not a one-liner at each call
    // site. Appending here would produce "primerocorregido" — the bug this
    // shipped as once.
    final events = Stream<ChatEvent>.fromIterable(const [
      TextDelta('primero'),
      TextDelta('corregido', isReset: true),
      TextDelta(' y sigue'),
    ]);

    expect(await collectText(events), 'corregido y sigue');
  });

  test('collectText ignores everything that is not text', () async {
    final events = Stream<ChatEvent>.fromIterable(const [
      SearchStarted(['q']),
      TextDelta('la respuesta'),
      ConversationTitled('un título'),
      ReplyCompleted(),
      TurnCompleted(actualModel: 'gpt-5-6', finishReason: 'stop'),
    ]);

    expect(await collectText(events), 'la respuesta');
  });

  test('collectText works over sendWithRotation, which is the rotating path',
      () async {
    final client = ChatGptClient(transport: FakeTransport());
    final session = client.newSession();

    final reply = await collectText(client.sendWithRotation(session, 'hola'));

    expect(reply.trim(), 'hola mundo');
    client.close();
  });

  test('an error still surfaces rather than returning a partial answer',
      () async {
    final transport = FakeTransport()
      ..failures[0] = const TransportException('la red se cayó');
    final session = ChatGptClient(transport: transport).newSession();

    expect(session.ask('hola'), throwsA(isA<TransportException>()));
  });
}
