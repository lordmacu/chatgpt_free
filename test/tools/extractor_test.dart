import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/tools.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

const FunctionTool _weather = FunctionTool(
  name: 'get_weather',
  description: 'Current weather for a city',
  parameters: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
    'required': ['city'],
  },
);

/// An extractor whose upstream answers exactly [replies], in order.
({ToolExtractor extractor, FakeTransport transport}) harness(
    List<String> replies) {
  final transport = FakeTransport(replies: replies);
  return (
    extractor: ToolExtractor(client: ChatGptClient(transport: transport)),
    transport: transport,
  );
}

void main() {
  test('one message turns a request into a call', () async {
    final h = harness([
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima"}}]}',
    ]);

    final result = await h.extractor
        .extract('weather in Lima', functions: const [_weather]);

    expect(result, isA<ToolCallsExtracted>());
    final calls = (result as ToolCallsExtracted).calls;
    expect(calls.single.name, 'get_weather');
    expect(calls.single.arguments, {'city': 'Lima'});
    expect(result.requests, 1, reason: 'the happy path is one message');
    expect(h.transport.sentBodies, hasLength(1));
  });

  test('the manifest rides the user turn, with the server-side tools off',
      () async {
    // Both halves of the measured design: the manifest is in the message the
    // model reads as the user's, and search is off — with it on, the model
    // answers the question itself instead of delegating.
    final h = harness(['<<<NO_TOOL>>>']);
    await h.extractor.extract('weather in Lima', functions: const [_weather]);

    final body = h.transport.sentBodies.single;
    final sent = (((body['messages'] as List).single as Map)['content']
        as Map)['parts'] as List;
    expect('${sent.single}', contains('get_weather'));
    expect('${sent.single}', contains('AVAILABLE FUNCTIONS'));
    expect(body['force_use_search'], false);
    expect(body['force_use_tools'], false);
  });

  test('no declared function fits: a decision, not an error', () async {
    final h = harness(['<<<NO_TOOL>>>']);

    final result = await h.extractor
        .extract('tell me a joke', functions: const [_weather]);

    expect(result, isA<NoToolCall>());
    expect((result as NoToolCall).errors, isEmpty);
    expect(result.requests, 1);
  });

  test('a missing required parameter is reported, never invented', () async {
    final h = harness([
      '<<<NEED_INFO>>>{"function":"get_weather","missing":["city"]}',
    ]);

    final result = await h.extractor
        .extract('what is the weather', functions: const [_weather]);

    expect(result, isA<ToolInfoNeeded>());
    expect((result as ToolInfoNeeded).missing, ['city']);
    expect(result.function, 'get_weather');
  });

  test('an unreadable first reply is repaired with a second message', () async {
    final h = harness([
      'Sure! It is sunny in Lima right now.',
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima"}}]}',
    ]);

    final result = await h.extractor
        .extract('weather in Lima', functions: const [_weather]);

    expect(result, isA<ToolCallsExtracted>());
    expect(result.requests, 2);
    expect(result.notes, contains('repaired'));
  });

  test('the repair prompt carries what was wrong with the first answer',
      () async {
    final h = harness([
      // Schema-invalid: city must be a string.
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather","arguments":{"city":7}}]}',
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima"}}]}',
    ]);

    await h.extractor.extract('weather in Lima', functions: const [_weather]);

    final second = ((((h.transport.sentBodies[1]['messages'] as List).single
            as Map)['content'] as Map)['parts'] as List)
        .single;
    expect('$second', contains('city: expected string'));
    expect('$second', contains('rejected'));
  });

  test('a repair that also fails does not pretend to have succeeded', () async {
    final h = harness(['still prose', 'still prose again']);

    final result = await h.extractor
        .extract('weather in Lima', functions: const [_weather]);

    expect(result, isA<NoToolCall>());
    expect(result.notes, contains('repair-failed'));
    expect(result.requests, 2);
  });

  test('verify replaces the call when the audit is valid', () async {
    final h = harness([
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima"}}]}',
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima, Peru"}}]}',
    ]);

    final result = await h.extractor.extract('weather in Lima, Peru',
        functions: const [_weather], verify: true);

    expect((result as ToolCallsExtracted).calls.single.arguments,
        {'city': 'Lima, Peru'});
    expect(result.requests, 2);
    expect(result.notes, contains('verified'));
  });

  test('a junk audit is discarded, keeping the good first pass', () async {
    final h = harness([
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima"}}]}',
      'I could not find anything wrong.',
    ]);

    final result = await h.extractor
        .extract('weather in Lima', functions: const [_weather], verify: true);

    expect((result as ToolCallsExtracted).calls.single.arguments,
        {'city': 'Lima'});
    expect(result.notes, isNot(contains('verified')));
  });

  test('an audit that returns a schema-invalid call is discarded too',
      () async {
    final h = harness([
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
          '"arguments":{"city":"Lima"}}]}',
      '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather","arguments":{}}]}',
    ]);

    final result = await h.extractor
        .extract('weather in Lima', functions: const [_weather], verify: true);

    expect((result as ToolCallsExtracted).calls.single.arguments,
        {'city': 'Lima'});
  });

  test('verify does not run when there was nothing to audit', () async {
    final h = harness(['<<<NO_TOOL>>>']);

    final result = await h.extractor
        .extract('tell me a joke', functions: const [_weather], verify: true);

    expect(result.requests, 1, reason: 'no calls, nothing to audit');
    expect(h.transport.sentBodies, hasLength(1));
  });

  group('tool choice', () {
    test('auto offers the model a way out', () async {
      final h = harness(['<<<NO_TOOL>>>']);
      await h.extractor.extract('hola', functions: const [_weather]);

      final prompt = ((((h.transport.sentBodies.single['messages'] as List)
              .single as Map)['content'] as Map)['parts'] as List)
          .single;
      expect('$prompt', contains('<<<NO_TOOL>>>   (no declared function fits'));
    });

    test('any removes it', () async {
      final h = harness([
        '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
            '"arguments":{"city":"Lima"}}]}',
      ]);
      await h.extractor
          .extract('hola', functions: const [_weather], choice: ToolChoice.any);

      final prompt = ((((h.transport.sentBodies.single['messages'] as List)
              .single as Map)['content'] as Map)['parts'] as List)
          .single;
      expect('$prompt', contains('You MUST call a function'));
      expect('$prompt', contains('is forbidden for this request'));
    });

    test('naming a function pins it', () async {
      final h = harness([
        '<<<TOOL_CALL>>>{"calls":[{"name":"get_weather",'
            '"arguments":{"city":"Lima"}}]}',
      ]);
      await h.extractor.extract('hola',
          functions: const [_weather],
          choice: const ToolChoice.function('get_weather'));

      final prompt = ((((h.transport.sentBodies.single['messages'] as List)
              .single as Map)['content'] as Map)['parts'] as List)
          .single;
      expect('$prompt', contains('You MUST call the function "get_weather"'));
    });
  });

  test('declaring no functions is a programming error, caught before spending',
      () async {
    final h = harness(['<<<NO_TOOL>>>']);

    expect(() => h.extractor.extract('hola', functions: const []),
        throwsArgumentError);
    expect(h.transport.sentBodies, isEmpty, reason: 'no message was spent');
  });

  test('an extraction never overwrites the app persisted device id', () async {
    // A throwaway session that wrote to the app's store would replace the
    // device the user's own conversation resumes from.
    final store = InMemoryStore();
    await store.write('device_id', 'the-app-device');

    final transport = FakeTransport(replies: ['<<<NO_TOOL>>>']);
    final client = ChatGptClient(transport: transport, store: store);
    await ToolExtractor(client: client)
        .extract('hola', functions: const [_weather]);

    expect(await store.read('device_id'), 'the-app-device');
    expect(transport.sentDeviceIds.single, isNot('the-app-device'),
        reason: 'the extraction ran as its own device');
  });
}
