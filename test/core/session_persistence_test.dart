import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test(
      'ChatGptSession.restore resumes device_id and conversation_id from a '
      'populated store (Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();
    await store.write('device_id', 'saved-device-id');
    await store.write('conversation_id', 'saved-conversation-id');

    final session = await ChatGptSession.restore(
      transport: FakeTransport(),
      store: store,
    );

    expect(session.deviceId, 'saved-device-id');
    expect(session.conversationId, 'saved-conversation-id');
  });

  test('ChatGptSession.restore starts fresh when the store is empty '
      '(Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();

    final session = await ChatGptSession.restore(
      transport: FakeTransport(),
      store: store,
    );

    expect(session.deviceId, isNotEmpty);
    expect(session.conversationId, isNull);
  });

  test(
      'the plain constructor never reads the store, even when one is '
      'supplied — restoration is opt-in via ChatGptSession.restore '
      '(Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();
    await store.write('device_id', 'someone-elses-device-id');
    await store.write('conversation_id', 'someone-elses-conversation-id');

    final session = ChatGptSession(transport: FakeTransport(), store: store);

    expect(session.deviceId, isNot('someone-elses-device-id'));
    expect(session.conversationId, isNull);
  });

  test(
      'the plain constructor persists its fresh device id so a later '
      'restore can find it (Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();

    final session = ChatGptSession(transport: FakeTransport(), store: store);
    // The write is fire-and-forget (the constructor stays synchronous), so
    // give the event loop one turn to let it land.
    await Future<void>.delayed(Duration.zero);

    expect(await store.read('device_id'), session.deviceId);
  });

  test(
      'rotateDevice persists the new device id and clears the stored '
      'conversation id (Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();
    await store.write('conversation_id', 'stale-conversation-id');
    final session = ChatGptSession(transport: FakeTransport(), store: store);
    await Future<void>.delayed(Duration.zero);

    session.rotateDevice();
    await Future<void>.delayed(Duration.zero);

    expect(await store.read('device_id'), session.deviceId);
    expect(await store.read('conversation_id'), isNull);
  });

  test('reset clears both persisted keys (Fix round 1, Finding 2)',
      () async {
    final store = InMemoryStore();
    final session = ChatGptSession(transport: FakeTransport(), store: store);
    await store.write('conversation_id', 'some-conversation-id');

    await session.reset();

    expect(await store.read('conversation_id'), isNull);
    expect(await store.read('device_id'), session.deviceId);
  });
}
