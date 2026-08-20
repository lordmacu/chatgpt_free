import 'dart:async';
import 'dart:convert';

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

/// A transport whose [stream] calls are driven entirely by the test: each
/// call gets its own [StreamController] that the test feeds (or fails) by
/// hand, so two overlapping [ChatGptSession.send] calls can be sequenced
/// deterministically instead of racing on real I/O timing.
class _ControlledTransport implements Transport {
  final List<Map<String, dynamic>> sentBodies = [];
  final List<StreamController<List<int>>> controllers = [];

  @override
  Future<Stream<List<int>>> stream(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async {
    sentBodies.add(body);
    final controller = StreamController<List<int>>();
    controllers.add(controller);
    return controller.stream;
  }

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

/// A minimal, complete SSE turn: sets up the message document, appends one
/// word of text, then signals the end of the stream. Hand-built rather than
/// read from a fixture so a test can feed it through a [StreamController] at
/// whatever moment it chooses.
final List<int> _minimalCompleteTurnSse = utf8.encode(
  'data: {"p":"","o":"add","v":{"message":{"content":'
  '{"parts":[""]},"metadata":{}}}}\n\n'
  'data: {"p":"/message/content/parts/0","o":"append","v":"ok"}\n\n'
  'data: [DONE]\n\n',
);

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
    expect(
        transport.sentBodies.last['conversation_id'], session.conversationId);
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

  // Final review, Blocker 5: ChatGptClient.limits()/models()/translate() all
  // queried a throwaway probe device id, so limits() always reported an
  // untouched device — never any session's real spend. Quota is per
  // device_id, which is the entire premise of the rotation feature, so
  // limits() belongs on the session itself.

  test(
      "limits() reports on this session's own device id, not a probe "
      '(Final review, Blocker 5)', () async {
    final transport = FakeTransport()
      ..getResponse = jsonEncode({
        'limits_progress': [
          {'feature_name': 'file_upload', 'remaining': 3}
        ],
      });
    final session = ChatGptSession(transport: transport);

    final limits = await session.limits();

    expect(limits.remaining['file_upload'], 3);
    expect(transport.sentPostDeviceIds, [session.deviceId]);
  });

  test(
      'limits() reflects the device id after a rotation, not the '
      'abandoned one (Final review, Blocker 5)', () async {
    final transport = FakeTransport()..getResponse = jsonEncode({});
    final session = ChatGptSession(transport: transport);

    session.rotateDevice();
    await session.limits();

    expect(transport.sentPostDeviceIds, [session.deviceId]);
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

    await session.send('resume esto', attachments: const [
      TextAttachment(name: 'a.txt', content: 'contenido secreto')
    ]).drain<void>();

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

  test(
      'a truncated multi-byte UTF-8 sequence surfaces as ProtocolException '
      'through send(), not a raw FormatException, and leaves history clean '
      '(Final review, Blocker 3)', () async {
    // Regression: nothing wrapped the response body stream, so a connection
    // dropping mid multi-byte UTF-8 character let a raw FormatException
    // escape send() (and, transitively, ChatGptClient.sendWithRotation)
    // unclassified — failing `is ChatGptException`. readSse now reclassifies
    // it as ProtocolException before it reaches here.
    final transport = _ControlledTransport();
    final session = ChatGptSession(transport: transport);

    final result = session.send('hola').toList();
    // Let send() run up to (and await) its _transport.stream() call before
    // reaching into transport.controllers — otherwise the controller for
    // this call does not exist yet.
    await Future<void>.delayed(Duration.zero);
    // 0xC3 is the lead byte of a 2-byte UTF-8 sequence; closing the stream
    // right after it, with no continuation byte, is what a connection
    // dropping mid-character produces.
    transport.controllers.single
      ..add([...utf8.encode('data: caf'), 0xC3])
      ..close();

    await expectLater(result, throwsA(isA<ProtocolException>()));

    // Same contract as every other mid-stream failure: no orphaned turns
    // left behind for the next send() to fold into its prompt.
    expect(session.history, isEmpty);
  });

  test(
      'an overlapping call is unaffected when another call unwinds after a '
      'mid-stream failure (Fix round 3)', () async {
    // Fix round 2 tried to prevent this with a reentrancy guard; that guard
    // could brick a session forever (see the task report), so round 3
    // removed it. Overlapping send() calls on one session ARE possible
    // again, which means the round-1 unwind's real defect matters again: it
    // removed the "last two" _history entries by position, trusting they
    // were this call's own. This test proves the fix -- identity-based
    // removal -- actually holds under exactly the interleaving that broke
    // the old removeLast() approach.
    final transport = _ControlledTransport();
    final session = ChatGptSession(transport: transport);

    // Start the FIRST call and let it stage its user turn and streaming
    // assistant placeholder, then leave it hanging: nothing is fed to its
    // controller yet.
    Object? firstError;
    final firstDone = Completer<void>();
    session.send('first').listen(
      (_) {},
      onError: (Object e) {
        firstError = e;
        if (!firstDone.isCompleted) firstDone.complete();
      },
      onDone: () {
        if (!firstDone.isCompleted) firstDone.complete();
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(session.history.length, 2,
        reason: 'the first call should have staged its turn by now');
    final firstUser = session.history[0];
    final firstAssistant = session.history[1];

    // Run a SECOND call to completion while the first is still pending. Its
    // entries land after the first call's -- at the position a count-based
    // `removeLast()` unwind would target. Start draining before feeding its
    // controller: draining begins consuming the stream (so send() actually
    // runs and calls _transport.stream(), creating controllers[1]) without
    // blocking, and only resolves once the fed bytes let the turn finish.
    final secondDone = session.send('second').drain<void>();
    await Future<void>.delayed(Duration.zero);
    transport.controllers[1].add(_minimalCompleteTurnSse);
    await secondDone;
    expect(session.history.length, 4);
    final secondUser = session.history[2];
    final secondAssistant = session.history[3];

    // Now fail the FIRST call's stream, mid-turn.
    final error = Exception('dropped mid-turn');
    transport.controllers[0].addError(error);
    await firstDone.future;
    expect(firstError, same(error));

    // Only the first call's own two entries were removed -- by identity. A
    // count-based `removeLast()` x2 unwind would instead delete the SECOND
    // call's entries (the ones actually last), which is exactly the
    // corruption this test exists to catch.
    expect(session.history.length, 2);
    expect(identical(session.history[0], secondUser), isTrue);
    expect(identical(session.history[1], secondAssistant), isTrue);
    expect(session.history.any((m) => identical(m, firstUser)), isFalse);
    expect(session.history.any((m) => identical(m, firstAssistant)), isFalse);
  });
}
