import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/src/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test('streams text and records the turn in history', () async {
    final transport = FakeTransport();
    final session = ChatGptSession(transport: transport);

    final events = await session.send('Di hola mundo').toList();
    final text = events.whereType<TextDelta>().map((e) => e.text).join();

    expect(text.toLowerCase(), contains('hola mundo'));
    expect(session.history.length, 2);
    expect(session.history.first.role, 'user');
    expect(session.history.last.role, 'assistant');
    expect(session.history.last.isStreaming, isFalse);
  });

  test('learns the conversation id and reuses it on the next turn', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text']);
    final session = ChatGptSession(transport: transport);

    await session.send('uno').drain<void>();
    expect(session.conversationId, isNotEmpty);

    await session.send('dos').drain<void>();
    expect(transport.sentBodies.last['conversation_id'], session.conversationId);
  });

  test('validates options before touching the transport', () async {
    final transport = FakeTransport();
    final session = ChatGptSession(transport: transport);

    await expectLater(
      session.send('x', options: const SendOptions(model: '')).toList(),
      throwsA(isA<InvalidRequestException>()),
    );
    expect(transport.sentBodies, isEmpty);
  });

  test('rotateDevice issues a new id and forgets the conversation', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text']);
    final session = ChatGptSession(transport: transport);

    await session.send('uno').drain<void>();
    final firstDevice = session.deviceId;
    expect(session.conversationId, isNotEmpty);

    session.rotateDevice();

    expect(session.deviceId, isNot(firstDevice));
    expect(session.conversationId, isNull);
  });

  test('replays history inline after a rotation so context survives', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text']);
    final session = ChatGptSession(transport: transport);

    await session.send('me llamo Cristian').drain<void>();
    session.rotateDevice();
    await session.send('cómo me llamo?').drain<void>();

    final parts = ((transport.sentBodies.last['messages'] as List).single
        as Map)['content'] as Map;
    final prompt = (parts['parts'] as List).single as String;

    expect(prompt, contains('me llamo Cristian'));
    expect(prompt, endsWith('cómo me llamo?'));
  });

  test('attachments reach the prompt', () async {
    final transport = FakeTransport();
    final session = ChatGptSession(transport: transport);

    await session
        .send('resume esto', attachments: const [
          TextAttachment(name: 'a.txt', content: 'contenido secreto')
        ])
        .drain<void>();

    final parts = ((transport.sentBodies.single['messages'] as List).single
        as Map)['content'] as Map;
    expect((parts['parts'] as List).single, contains('contenido secreto'));
  });

  test(
      'a mid-stream transport failure leaves history clean for a retry '
      '(Fix round 1, Finding 1)', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text']);
    final droppedConnection = Exception('dropped mid-turn');
    // Let the first call deliver the "hola mundo" delta — proving a real,
    // partially-assembled assistant reply was already folded into history —
    // then blow up before the stream would naturally complete.
    transport.midStreamCutAfter[0] = '"hola mundo"';
    transport.midStreamFailures[0] = droppedConnection;
    final session = ChatGptSession(transport: transport);

    await expectLater(
      session.send('hola').toList(),
      throwsA(same(droppedConnection)),
    );

    // The failed attempt must be entirely invisible: no orphaned user turn,
    // no assistant bubble stuck at isStreaming: true.
    expect(session.history, isEmpty);

    // A same-message retry must behave exactly like a fresh first attempt —
    // one user turn, one completed assistant turn, and (since history was
    // rolled back to empty) no replayed-history wrapper in the prompt.
    await session.send('hola').drain<void>();
    expect(session.history.length, 2);
    expect(session.history.where((m) => m.role == 'user').length, 1);
    expect(session.history.every((m) => !m.isStreaming), isTrue);

    final parts = ((transport.sentBodies.last['messages'] as List).single
        as Map)['content'] as Map;
    expect((parts['parts'] as List).single, 'hola');
  });

  test(
      'a transport failure on the first turn keeps the system prompt '
      'pending for the retry (Fix round 1, Finding 2)', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text']);
    final rateLimited = Exception('rate limited');
    transport.failures[0] = rateLimited;
    final session = ChatGptSession(
      transport: transport,
      systemPrompt: 'Be concise.',
    );

    await expectLater(
      session.send('hola').toList(),
      throwsA(same(rateLimited)),
    );

    // The retry is still "the first turn" as far as the session is
    // concerned: the system prompt was never actually delivered, so it must
    // be sent again, not silently dropped.
    await session.send('hola').drain<void>();

    final parts = ((transport.sentBodies.last['messages'] as List).single
        as Map)['content'] as Map;
    final prompt = (parts['parts'] as List).single as String;
    expect(prompt, '[System instructions: Be concise.]\n\nhola');
  });

  test('close() does not close an injected transport (Fix round 1, Finding 3)',
      () {
    final transport = FakeTransport();
    final session = ChatGptSession(transport: transport);

    session.close();

    expect(transport.closeCalled, isFalse);
  });
}
