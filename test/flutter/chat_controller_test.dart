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
