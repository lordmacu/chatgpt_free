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
}
