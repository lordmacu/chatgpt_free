import 'package:chatgpt_free/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// The functions these replies are read against. Detection is gated on this:
/// it is what separates "the model invoked a tool" from "the model wrote about
/// JSON".
const Set<String> kNames = {'get_weather', 'f', 'first', 'second', 'ok', 'now'};

void main() {
  test('reads a clean envelope', () {
    final envelope = parseToolEnvelope(
        '$kToolCallMarker{"calls":[{"name":"get_weather",'
        '"arguments":{"city":"Lima"}}]}',
        kNames);

    final calls = (envelope as EnvelopeCalls).calls;
    expect(calls, hasLength(1));
    expect(calls.single.name, 'get_weather');
    expect(calls.single.arguments, {'city': 'Lima'});
    expect(envelope.notes, isEmpty);
  });

  test('two cities means two calls', () {
    final envelope = parseToolEnvelope(
        '$kToolCallMarker{"calls":['
        '{"name":"get_weather","arguments":{"city":"Lima"}},'
        '{"name":"get_weather","arguments":{"city":"Quito"}}]}',
        kNames);

    expect((envelope as EnvelopeCalls).calls.map((c) => c.arguments['city']),
        ['Lima', 'Quito']);
  });

  test('a fenced envelope is read, and noted rather than rejected', () {
    final envelope = parseToolEnvelope(
        '```json\n$kToolCallMarker{"calls":[{"name":"f","arguments":{}}]}\n```',
        kNames);

    expect(envelope, isA<EnvelopeCalls>());
    expect(envelope.notes, contains('fenced'));
  });

  test('prose before the marker is tolerated and noted', () {
    final envelope = parseToolEnvelope(
        'Sure, here you go:\n$kToolCallMarker{"calls":[{"name":"f","arguments":{}}]}',
        kNames);

    expect((envelope as EnvelopeCalls).calls, hasLength(1));
    expect(envelope.notes, contains('prose-before'));
  });

  test('a repeated marker reads the first envelope only', () {
    final envelope = parseToolEnvelope(
        '$kToolCallMarker{"calls":[{"name":"first","arguments":{}}]}'
        '$kToolCallMarker{"calls":[{"name":"second","arguments":{}}]}',
        kNames);

    final calls = (envelope as EnvelopeCalls).calls;
    expect(calls.single.name, 'first');
    expect(envelope.notes, contains('duplicate-marker'));
  });

  test('no-tool is a decision, not a failure', () {
    final envelope = parseToolEnvelope(kNoToolMarker, kNames);

    expect((envelope as EnvelopeCalls).calls, isEmpty);
  });

  test('need-info carries which parameters were missing', () {
    final envelope = parseToolEnvelope(
        '$kNeedInfoMarker{"function":"book_flight","missing":["origin","date"]}',
        kNames);

    expect(envelope, isA<EnvelopeNeedInfo>());
    expect((envelope as EnvelopeNeedInfo).function, 'book_flight');
    expect(envelope.missing, ['origin', 'date']);
  });

  test('an ordinary answer is not mistaken for a call', () {
    // The whole reason for a marker rather than "reply in JSON": a reply that
    // happens to contain JSON is still prose.
    final envelope = parseToolEnvelope(
        'The config looks like {"calls":[{"name":"x"}]} in most setups.',
        kNames);

    expect(envelope, isA<EnvelopeUnreadable>());
    expect(envelope.notes, contains('no-marker'));
  });

  test('a marker with broken JSON after it is unreadable, not empty', () {
    // Reporting "no calls" here would be a silent wrong answer; the caller
    // needs to know the reply has to be repaired.
    final envelope = parseToolEnvelope('$kToolCallMarker{"calls":[{{{', kNames);

    expect(envelope, isA<EnvelopeUnreadable>());
    expect(envelope.notes, contains('invalid-json'));
  });

  test('a partly-valid batch is refused whole, not silently pruned', () {
    // This used to keep the good entry and drop the nameless one. All-or-
    // nothing is the safer rule: a list where only some entries qualify is
    // far more likely to be data than a batch of calls, and a batch the model
    // did make deserves a repair round trip rather than being quietly
    // shortened behind the caller's back.
    final envelope = parseToolEnvelope(
        '$kToolCallMarker{"calls":[{"arguments":{"city":"Lima"}},'
        '{"name":"ok","arguments":{}}]}',
        kNames);

    expect(envelope, isA<EnvelopeUnreadable>());
  });

  test('a call with no arguments at all becomes an empty argument map', () {
    final envelope =
        parseToolEnvelope('$kToolCallMarker{"calls":[{"name":"now"}]}', kNames);

    expect((envelope as EnvelopeCalls).calls.single.arguments, isEmpty);
  });

  test('OpenAI shape: arguments is a JSON string, not an object', () {
    final call = ToolCall(name: 'get_weather', arguments: {'city': 'Lima'});

    expect(call.toJson(), {
      'id': call.id,
      'type': 'function',
      'function': {'name': 'get_weather', 'arguments': '{"city":"Lima"}'},
    });
    expect(call.id, startsWith('call_'));
  });

  group('FunctionTool.fromJson', () {
    test('reads the wrapped OpenAI tools shape', () {
      final tool = FunctionTool.fromJson({
        'type': 'function',
        'function': {
          'name': 'get_weather',
          'description': 'Weather for a city',
          'parameters': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
        },
      });

      expect(tool.name, 'get_weather');
      expect(tool.description, 'Weather for a city');
      expect(tool.parameters['type'], 'object');
    });

    test('reads a bare function object too — both are in circulation', () {
      final tool = FunctionTool.fromJson({'name': 'now'});

      expect(tool.name, 'now');
      expect(tool.parameters, {'type': 'object', 'properties': {}});
    });
  });
}
