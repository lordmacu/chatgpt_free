@Tags(['live'])
library;

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/tools.dart';
import 'package:flutter_test/flutter_test.dart';

const FunctionTool _weather = FunctionTool(
  name: 'get_weather',
  description: 'Current weather conditions for one city',
  parameters: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string', 'description': 'City name'},
      'units': {
        'type': 'string',
        'enum': ['celsius', 'fahrenheit'],
      },
    },
    'required': ['city'],
  },
);

const FunctionTool _sendEmail = FunctionTool(
  name: 'send_email',
  description: 'Send an email to one recipient',
  parameters: {
    'type': 'object',
    'properties': {
      'to': {'type': 'string'},
      'subject': {'type': 'string'},
      'body': {'type': 'string'},
    },
    'required': ['to', 'subject', 'body'],
  },
);

void main() {
  // The claim the whole subsystem rests on: a backend with no function calling
  // can still be made to produce one, from the user turn of a throwaway
  // session. Each of these spends real anonymous quota.
  test('one request, two cities, two calls', () async {
    final client = ChatGptClient();
    final result = await ToolExtractor(client: client).extract(
      'What is the weather in Lima and in Quito?',
      functions: const [_weather, _sendEmail],
    );
    client.close();

    expect(result, isA<ToolCallsExtracted>(),
        reason: 'the model answered instead of delegating: ${result.raw}');
    final calls = (result as ToolCallsExtracted).calls;

    expect(calls, hasLength(2), reason: 'one call per distinct arguments');
    expect(calls.map((c) => c.name), everyElement('get_weather'));
    expect(
      calls.map((c) => '${c.arguments['city']}'.toLowerCase()).join(' '),
      allOf(contains('lima'), contains('quito')),
    );
    // Whatever it produced must satisfy the schema it was handed.
    expect(validateToolCalls(calls, const [_weather, _sendEmail]), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a request no declared function covers gets no call', () async {
    final client = ChatGptClient();
    final result = await ToolExtractor(client: client).extract(
      'Write me a haiku about the sea.',
      functions: const [_weather, _sendEmail],
    );
    client.close();

    // A false positive is the expensive failure: an app would run a function
    // the user never asked for.
    expect(result, isA<NoToolCall>(), reason: result.raw);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a missing required parameter is asked for, not invented', () async {
    final client = ChatGptClient();
    final result = await ToolExtractor(client: client).extract(
      'Send an email to ana@example.com.',
      functions: const [_sendEmail],
    );
    client.close();

    // Subject and body were never stated. Inventing them validates cleanly
    // against the schema, which is exactly what makes it dangerous.
    expect(result, isA<ToolInfoNeeded>(), reason: result.raw);
    expect((result as ToolInfoNeeded).missing.join(' ').toLowerCase(),
        anyOf(contains('subject'), contains('body')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
