import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/src/core/client.dart';
import 'package:chatgpt_free/src/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test('rotates the device and retries once on a rate limit', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text'])
      ..failures[0] = const RateLimitedException('limit per hour');
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport);

    final events =
        await client.sendWithRotation(session, 'hola').toList();

    expect(events.whereType<QuotaRotated>(), hasLength(1));
    expect(
      events.whereType<TextDelta>().map((e) => e.text).join().toLowerCase(),
      contains('hola mundo'),
    );
    expect(transport.sentDeviceIds.length, 2);
    expect(transport.sentDeviceIds[0], isNot(transport.sentDeviceIds[1]));
  });

  test('surfaces QuotaExceededException when the retry also fails', () async {
    final transport = FakeTransport(fixtures: ['plain_text'])
      ..failures[0] = const RateLimitedException('limit')
      ..failures[1] = const RateLimitedException('limit again');
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport);

    await expectLater(
      client.sendWithRotation(session, 'hola').toList(),
      throwsA(isA<QuotaExceededException>()),
    );
    expect(transport.sentDeviceIds.length, 2);
  });

  test('does not rotate on a non-quota error', () async {
    final transport = FakeTransport(fixtures: ['plain_text'])
      ..failures[0] = const TransportException('socket closed');
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport);

    await expectLater(
      client.sendWithRotation(session, 'hola').toList(),
      throwsA(isA<TransportException>()),
    );
    expect(transport.sentDeviceIds.length, 1);
  });

  test('a rotation does not duplicate the user turn in history', () async {
    final transport = FakeTransport(fixtures: ['plain_text', 'plain_text'])
      ..failures[0] = const RateLimitedException('limit per hour');
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport);

    await client.sendWithRotation(session, 'hola').drain<void>();

    expect(session.history.where((m) => m.role == 'user'), hasLength(1));
    expect(session.history, hasLength(2));
  });

  test('does not rotate on a silent model downgrade', () async {
    final transport = FakeTransport(fixtures: ['plain_text']);
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport);

    final events = await client
        .sendWithRotation(session, 'hola',
            options: const SendOptions(model: 'gpt-5-6-imaginary'))
        .toList();

    expect(events.whereType<ModelDowngraded>(), hasLength(1));
    expect(events.whereType<QuotaRotated>(), isEmpty);
    expect(transport.sentDeviceIds.length, 1);
  });
}
