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

  // Task 17: per-turn SendOptions, mutable model/webSearch, and the
  // streaming-setter guard.

  group('per-turn SendOptions precedence', () {
    test('omitting options builds SendOptions from the controller\'s own '
        'model and webSearch', () async {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-5',
        webSearch: true,
      );

      await controller.send('hola');

      expect(transport.sentBodies.single['model'], 'gpt-5-5');
      expect(transport.sentBodies.single['force_use_search'], true);
    });

    test('an explicit SendOptions is used verbatim, not merged with the '
        'controller\'s own settings', () async {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-5',
        webSearch: true,
      );

      // The explicit options below name a different model and leave
      // webSearch at SendOptions' own default (null) — verbatim precedence
      // means neither is filled back in from the controller.
      await controller.send('hola',
          options: const SendOptions(model: 'gpt-5-6-mini'));

      final body = transport.sentBodies.single;
      expect(body['model'], 'gpt-5-6-mini');
      expect(body.containsKey('force_use_search'), isFalse);
    });

    test('attachments pass through to the session', () async {
      final transport = FakeTransport();
      final controller =
          ChatController(client: ChatGptClient(transport: transport));

      await controller.send('resume esto', attachments: const [
        TextAttachment(name: 'a.txt', content: 'contenido secreto'),
      ]);

      final parts = ((transport.sentBodies.single['messages'] as List).single
          as Map)['content'] as Map;
      expect((parts['parts'] as List).single, contains('contenido secreto'));
    });
  });

  // Fix round 1, Finding 1: verbatim precedence is a footgun when a caller
  // reaches for a bare `SendOptions(...)` literal to flip on one extra
  // feature — that silently resets `model` back to 'auto', with nothing
  // surfacing it (ModelDowngraded compares the now-wrong *requested*
  // model against the answering one, so it looks like a correct `auto`
  // request). currentOptions + copyWith is the fix: the documented,
  // tested way to extend the controller's own current settings instead of
  // starting from a bare literal.

  group('currentOptions', () {
    test('reflects the controller\'s current model and webSearch', () {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-6',
        webSearch: true,
      );

      expect(controller.currentOptions.model, 'gpt-5-6');
      expect(controller.currentOptions.webSearch, true);
    });

    test('reflects a setter call made after construction', () {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-6',
      );

      controller.model = 'gpt-5-5-mini';
      controller.webSearch = false;

      expect(controller.currentOptions.model, 'gpt-5-5-mini');
      expect(controller.currentOptions.webSearch, false);
    });

    test('the documented pattern — currentOptions.copyWith(...) — sends '
        'the picker\'s model, not SendOptions\' bare default', () async {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-6', // the "picker" selection this turn must keep
      );

      await controller.send(
        'turn this into a doc',
        options: controller.currentOptions.copyWith(canvas: true),
      );

      final body = transport.sentBodies.single;
      expect(body['model'], 'gpt-5-6'); // NOT SendOptions' 'auto' default
      expect(body['force_use_canvas'], true);
    });

    test('the footgun this fixes: a bare SendOptions(...) literal really '
        'does drop the picker\'s model to auto (documents the hazard '
        'currentOptions exists to avoid)', () async {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-6',
      );

      await controller.send(
        'turn this into a doc',
        options: const SendOptions(canvas: true),
      );

      // This is the hazard, not the recommendation — contrast with the
      // currentOptions.copyWith(...) test directly above.
      expect(transport.sentBodies.single['model'], 'auto');
    });
  });

  group('mutable model and webSearch', () {
    test('setting model calls notifyListeners()', () async {
      final transport = FakeTransport();
      final controller =
          ChatController(client: ChatGptClient(transport: transport));
      var notified = false;
      controller.addListener(() => notified = true);

      controller.model = 'gpt-5-5-mini';

      expect(controller.model, 'gpt-5-5-mini');
      expect(notified, isTrue);
    });

    test('setting webSearch calls notifyListeners()', () async {
      final transport = FakeTransport();
      final controller =
          ChatController(client: ChatGptClient(transport: transport));
      var notified = false;
      controller.addListener(() => notified = true);

      controller.webSearch = true;

      expect(controller.webSearch, isTrue);
      expect(notified, isTrue);
    });

    test('changing model mid-conversation keeps the transcript and the '
        'conversation id, not just the local list', () async {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-6',
      );

      await controller.send('primer turno');
      expect(controller.messages.length, 2);
      // plain_text.sse has no conversation_id on the first request — the
      // session only learns one from the response.
      expect(transport.sentBodies[0].containsKey('conversation_id'), isFalse);

      controller.model = 'gpt-5-5';
      await controller.send('segundo turno');

      // The transcript grew, it was not reset.
      expect(controller.messages.length, 4);
      expect(controller.messages[0].text, 'primer turno');
      expect(controller.messages[2].text, 'segundo turno');
      // The second request carries the conversation id learned from the
      // first response, and uses the newly-set model.
      expect(transport.sentBodies[1]['conversation_id'],
          '6a872769-b8e0-83ea-9bcb-c551963b63a8');
      expect(transport.sentBodies[1]['model'], 'gpt-5-5');
      // The device id (and so the session) was not thrown away either.
      expect(transport.sentDeviceIds[1], transport.sentDeviceIds[0]);
    });
  });

  group('mutating settings while a turn is streaming', () {
    test('setting model while streaming throws StateError and leaves the '
        'in-flight turn untouched', () async {
      final transport = FakeTransport();
      final controller = ChatController(
        client: ChatGptClient(transport: transport),
        model: 'gpt-5-6',
      );

      final future = controller.send('hola');
      expect(controller.isStreaming, isTrue);

      expect(() => controller.model = 'gpt-5-5', throwsStateError);
      expect(controller.model, 'gpt-5-6'); // unchanged

      controller.stop();
      await future.timeout(const Duration(seconds: 3));
    });

    test('setting webSearch while streaming throws StateError', () async {
      final transport = FakeTransport();
      final controller =
          ChatController(client: ChatGptClient(transport: transport));

      final future = controller.send('hola');
      expect(controller.isStreaming, isTrue);

      expect(() => controller.webSearch = true, throwsStateError);
      expect(controller.webSearch, isNull); // unchanged

      controller.stop();
      await future.timeout(const Duration(seconds: 3));
    });
  });
}
