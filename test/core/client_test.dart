import 'package:chatgpt_free/chatgpt_free.dart';
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

  // ALSO (not from the final review): rotating clears the hourly cap
  // immediately in the normal case, but the cap has an IP component, so a
  // freshly rotated device can occasionally be born already limited under
  // sustained load. maxRotations lets an app opt into retrying more than
  // once; it defaults to 1 so existing behaviour is unchanged.

  test('maxRotations defaults to 1 — the pre-existing rotate-once behaviour '
      'is unchanged', () async {
    final transport = FakeTransport(fixtures: ['plain_text'])
      ..failures[0] = const RateLimitedException('limit')
      ..failures[1] = const RateLimitedException('limit again');
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport);

    await expectLater(
      client.sendWithRotation(session, 'hola').toList(),
      throwsA(isA<QuotaExceededException>()),
    );
    // Exactly one rotation: two attempts total.
    expect(transport.sentDeviceIds.length, 2);
  });

  test('a higher maxRotations keeps rotating past the first retry',
      () async {
    final transport = FakeTransport(fixtures: ['plain_text'])
      ..failures[0] = const RateLimitedException('limit 1')
      ..failures[1] = const RateLimitedException('limit 2')
      ..failures[2] = const RateLimitedException('limit 3');
    // failures[3] unset: the fourth attempt (after 3 rotations) succeeds.
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport, maxRotations: 3);

    final events =
        await client.sendWithRotation(session, 'hola').toList();

    expect(events.whereType<QuotaRotated>(), hasLength(3));
    expect(
      events.whereType<TextDelta>().map((e) => e.text).join().toLowerCase(),
      contains('hola mundo'),
    );
    // Four attempts total: three rotations plus the final success.
    expect(transport.sentDeviceIds.length, 4);
    expect(transport.sentDeviceIds.toSet().length, 4,
        reason: 'every attempt must use a distinct, freshly rotated device');
  });

  test('maxRotations exhausted: QuotaExceededException names how many '
      'rotations were attempted', () async {
    final transport = FakeTransport(fixtures: ['plain_text'])
      ..failures[0] = const RateLimitedException('limit 1')
      ..failures[1] = const RateLimitedException('limit 2')
      ..failures[2] = const RateLimitedException('limit 3');
    final session = ChatGptSession(transport: transport);
    final client = ChatGptClient(transport: transport, maxRotations: 2);

    await expectLater(
      client.sendWithRotation(session, 'hola').toList(),
      throwsA(isA<QuotaExceededException>().having(
        (e) => e.message,
        'message',
        contains('2 rotations'),
      )),
    );
    // Three attempts total: two rotations, then give up.
    expect(transport.sentDeviceIds.length, 3);
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
