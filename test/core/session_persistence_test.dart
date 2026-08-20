import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test(
      'ChatGptSession.restore resumes device_id and conversation_id from a '
      'populated store (Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();
    await store.write('device_id', 'saved-device-id');
    // The conversation id is namespaced under its own device id's key — see
    // Finding 6 below.
    await store.write(
        'conversation_id:saved-device-id', 'saved-conversation-id');

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
    await store.write('conversation_id:someone-elses-device-id',
        'someone-elses-conversation-id');

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
      'rotateDevice persists the new device id and clears the abandoned '
      "device's stored conversation id (Fix round 1, Finding 2)", () async {
    final store = InMemoryStore();
    final session = ChatGptSession(transport: FakeTransport(), store: store);
    await Future<void>.delayed(Duration.zero);
    final abandonedDeviceId = session.deviceId;
    await store.write(
        'conversation_id:$abandonedDeviceId', 'stale-conversation-id');

    session.rotateDevice();
    await Future<void>.delayed(Duration.zero);

    expect(await store.read('device_id'), session.deviceId);
    expect(await store.read('conversation_id:$abandonedDeviceId'), isNull);
  });

  test(
      'reset clears the abandoned device id\'s persisted conversation id '
      '(Fix round 1, Finding 2)', () async {
    final store = InMemoryStore();
    final session = ChatGptSession(transport: FakeTransport(), store: store);
    await Future<void>.delayed(Duration.zero);
    final abandonedDeviceId = session.deviceId;
    await store.write(
        'conversation_id:$abandonedDeviceId', 'some-conversation-id');

    await session.reset();

    expect(await store.read('conversation_id:$abandonedDeviceId'), isNull);
    expect(await store.read('device_id'), session.deviceId);
  });

  // Final review, minor: a store returning '' for an absent key must be
  // treated exactly like null — otherwise an empty string sails past a
  // `!= null` check and becomes this session's device id, landing on the
  // wire as an empty OAI-Device-Id header with no recovery path.

  test('restore treats an empty stored device id as absent, generating a '
      'fresh one (Final review, minor)', () async {
    final store = InMemoryStore();
    await store.write('device_id', '');

    final session = await ChatGptSession.restore(
      transport: FakeTransport(),
      store: store,
    );

    expect(session.deviceId, isNotEmpty);
    expect(session.conversationId, isNull);
  });

  test('restore treats an empty stored conversation id as absent '
      '(Final review, minor)', () async {
    final store = InMemoryStore();
    await store.write('device_id', 'saved-device-id');
    await store.write('conversation_id:saved-device-id', '');

    final session = await ChatGptSession.restore(
      transport: FakeTransport(),
      store: store,
    );

    expect(session.deviceId, 'saved-device-id');
    expect(session.conversationId, isNull);
  });

  // Final review, Finding 6: ChatGptClient shares one ChatGptStore across
  // every session it creates, and each session used to write the bare keys
  // 'device_id'/'conversation_id'. Two sessions from one client sharing a
  // persistent store — two chat tabs is the realistic trigger — could
  // interleave their writes so a later restore resumed one session's
  // conversation id paired with a different session's device id, a pairing
  // the backend never created.

  test(
      'two sessions sharing one client never let a stored conversation id '
      "pair with another session's device id (Final review, Finding 6)",
      () async {
    final store = InMemoryStore();
    final transport = FakeTransport(fixtures: ['plain_text']);
    final client = ChatGptClient(transport: transport, store: store);

    // Tab A opens first.
    final sessionA = client.newSession();
    await Future<void>.delayed(Duration.zero);

    // Tab B opens second: its constructor's device-id write lands after
    // A's, so the shared store's single 'device_id' key now points at B.
    final sessionB = client.newSession();
    await Future<void>.delayed(Duration.zero);
    expect(await store.read('device_id'), sessionB.deviceId);
    expect(sessionB.deviceId, isNot(sessionA.deviceId));

    // Tab A finishes a turn and learns its own conversation id. Under the
    // old unnamespaced scheme this write clobbered the shared bare
    // 'conversation_id' key with A's conversation — now sitting in the
    // store paired with B's device id.
    await sessionA.send('hola').drain<void>();
    expect(sessionA.conversationId, isNotEmpty);

    // A fresh restore must resume B's device id (the one actually saved)
    // without ever attaching A's conversation to it — B never sent a turn,
    // so it has no conversation of its own yet.
    final restored = await ChatGptSession.restore(
      transport: FakeTransport(),
      store: store,
    );

    expect(restored.deviceId, sessionB.deviceId);
    expect(restored.conversationId, isNot(sessionA.conversationId));
    expect(restored.conversationId, isNull);
  });
}
