import 'package:chatgpt_free/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test('appends the user turn, then streams the assistant reply', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    final notifications = <int>[];
    controller.addListener(() => notifications.add(controller.messages.length));

    await controller.send('Di hola mundo');

    expect(controller.messages.length, 2);
    expect(controller.messages.first.role, 'user');
    expect(controller.messages.last.text.toLowerCase(), contains('hola mundo'));
    expect(controller.isStreaming, isFalse);
    expect(notifications, isNotEmpty);
  });

  test('surfaces a downgrade notice the app can show', () async {
    final transport = FakeTransport();
    final controller = ChatController(
      client: ChatGptClient(transport: transport),
      model: 'gpt-5-6-imaginary',
    );

    await controller.send('hola');

    expect(controller.downgradeNotice, contains('gpt-5-6'));
  });

  // Final review, Blocker 4: the spec promises ChatController.retry(), and
  // there was no such method — nor a naive path to add one, since a failed
  // turn's user message does not survive: session.send's own catch unwinds
  // it out of history, so it is gone from controller.messages by the time
  // retry() could look for it there. ChatController now remembers the last
  // prompt it attempted itself.

  test('retry() resends the last prompt after a failure '
      '(Final review, Blocker 4)', () async {
    final transport = FakeTransport(fixtures: ['plain_text'])
      ..failures[0] = const TransportException('connection reset');
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    await controller.send('hola');
    expect(controller.error, isA<TransportException>());
    // The failed attempt's user turn does not survive — nothing left in
    // messages for a naive retry to recover the prompt from.
    expect(controller.messages, isEmpty);

    await controller.retry();

    expect(controller.error, isNull);
    expect(controller.messages.length, 2);
    expect(controller.messages.first.role, 'user');
    expect(controller.messages.first.text, 'hola');
    expect(controller.messages.last.text.toLowerCase(), contains('hola mundo'));
  });

  test('retry() is a safe no-op when nothing has been sent yet '
      '(Final review, Blocker 4)', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    await controller.retry();

    expect(controller.messages, isEmpty);
    expect(controller.isStreaming, isFalse);
    expect(transport.sentDeviceIds, isEmpty);
  });

  test('retry() is a safe no-op when the last send already succeeded '
      '(Final review, Blocker 4)', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    await controller.send('hola');
    expect(controller.messages.length, 2);
    expect(controller.error, isNull);

    await controller.retry();

    // Nothing to retry — no second turn sent.
    expect(controller.messages.length, 2);
    expect(transport.sentDeviceIds.length, 1);
  });

  test('clear empties the transcript', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    await controller.send('hola');
    await controller.clear();

    expect(controller.messages, isEmpty);
    expect(controller.downgradeNotice, isNull);
  });

  // Regression coverage for Fix round 1 / Finding 1: cancelling the
  // StreamSubscription never invokes onDone/onError, so those were the only
  // two places completing send()'s Completer. A caller awaiting send()
  // while stop()/clear()/dispose() fires mid-turn used to hang forever.
  // Each test below bounds the await with a short timeout so a regression
  // fails fast (with a TimeoutException) instead of hanging the suite.

  test('stop() mid-turn completes the pending send() future', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    final future = controller.send('hola');
    controller.stop();

    await future.timeout(const Duration(seconds: 3));

    expect(controller.isStreaming, isFalse);
  });

  test('clear() mid-turn completes the pending send() future', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    final future = controller.send('hola');
    final clearing = controller.clear();

    await future.timeout(const Duration(seconds: 3));
    await clearing.timeout(const Duration(seconds: 3));

    expect(controller.isStreaming, isFalse);
    expect(controller.messages, isEmpty);
  });

  test('dispose() mid-turn completes the pending send() future', () async {
    final transport = FakeTransport();
    final controller =
        ChatController(client: ChatGptClient(transport: transport));

    final future = controller.send('hola');
    controller.dispose();

    await future.timeout(const Duration(seconds: 3));
  });
}
