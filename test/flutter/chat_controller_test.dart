import 'package:chatgpt_free/src/core/client.dart';
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
}
