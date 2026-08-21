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

  test('answer gives the sources too, which ask cannot', () async {
    // The gap this closes: ask() returns the words, but citations arrive as a
    // separate event, so "the reply AND its sources" meant going back to a
    // stream for want of one field.
    final client =
        ChatGptClient(transport: FakeTransport(fixtures: ['web_search']));
    final session = client.newSession();

    final answer = await session.answer('capital of Mongolia');

    expect(answer.text, contains('Ulaanbaatar'));
    expect(answer.citations, isNotEmpty);
    expect(answer.citations.first.url, isNotEmpty);
    expect(answer.searchQueries, isNotEmpty);
    expect(answer.model, isNotEmpty);
    client.close();
  });

  test('answer carries the title the backend generated', () async {
    final client = ChatGptClient(transport: FakeTransport());
    final answer = await client.newSession().answer('Di hola mundo');

    expect(answer.title, 'Decir hola mundo');
    client.close();
  });

  test('answer carries the canvas document when there is one', () async {
    final client =
        ChatGptClient(transport: FakeTransport(fixtures: ['canvas']));
    final answer = await client.newSession().answer('escribe sobre el mar');

    expect(answer.canvas, isNotNull);
    expect(answer.canvas!.markdown, isNotEmpty);
    client.close();
  });

  test('answer reports the quota snapshot attached to the turn', () async {
    final client = ChatGptClient(transport: FakeTransport());
    final answer = await client.newSession().answer('hola');

    expect(answer.limits, isNotNull);
    expect(answer.limits!.remaining, isNotEmpty);
    expect(answer.limits!.resetAfter, isNotEmpty);
    client.close();
  });

  test('collectAnswer folds text exactly as collectText does', () async {
    final events = Stream<ChatEvent>.fromIterable(const [
      TextDelta('primero'),
      TextDelta('corregido', isReset: true),
      TextDelta(' y sigue'),
      TurnCompleted(actualModel: 'gpt-5-6', finishReason: 'stop'),
    ]);

    expect((await collectAnswer(events)).text, 'corregido y sigue');
  });

  test('collectAnswer records every rotation it took to get the answer',
      () async {
    final events = Stream<ChatEvent>.fromIterable(const [
      QuotaRotated('hourly limit'),
      TextDelta('por fin'),
      TurnCompleted(actualModel: 'gpt-5-6', finishReason: 'stop'),
    ]);

    final answer = await collectAnswer(events);
    expect(answer.rotations, ['hourly limit']);
    expect(answer.text, 'por fin');
  });
}
