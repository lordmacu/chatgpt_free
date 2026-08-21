import 'package:chatgpt_free/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// Detection and repair, ported from llm-libre's tool_emulator.
///
/// Every case here used to cost a repair round trip — one more message off an
/// anonymous hourly allowance — or, worse, produced the wrong call.

const FunctionTool _weather = FunctionTool(
  name: 'get_weather',
  parameters: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
      'days': {'type': 'integer'},
      'unit': {
        'type': 'string',
        'enum': ['celsius', 'fahrenheit'],
      },
    },
    'required': ['city'],
  },
);

const FunctionTool _email = FunctionTool(
  name: 'send_email',
  parameters: {
    'type': 'object',
    'properties': {
      'to': {'type': 'string'},
    },
    'required': ['to'],
  },
);

const List<FunctionTool> _funcs = [_weather, _email];
const Set<String> _names = {'get_weather', 'send_email'};

List<ToolCall>? parse(String text,
        [Set<String> names = _names, List<FunctionTool> funcs = _funcs]) =>
    detectToolCalls(text, names, functions: funcs);

void main() {
  group('soundness — the allow-list is the whole defence', () {
    test('a name nobody declared stays text', () {
      expect(parse('{"name": "launch_missiles", "arguments": {}}'), isNull);
    });

    test('no declared functions can never produce a call', () {
      expect(
          parse('{"name": "get_weather", "arguments": {}}', const {}), isNull);
    });

    test('prose about JSON is not a call', () {
      expect(
          parse('The config is a name/arguments pair in most setups.'), isNull);
    });
  });

  group('tool choice is enforced, not merely prompted', () {
    test('a pinned choice narrows the allow-list to itself', () {
      expect(allowedNames(_funcs, const ToolChoice.function('get_weather')),
          {'get_weather'});
      expect(allowedNames(_funcs, ToolChoice.auto), _names);
      expect(allowedNames(_funcs, ToolChoice.any), _names);
    });

    test('pinning one function rejects a call to another declared one', () {
      // The hole this closes: the pinned name used to live only in the prompt,
      // so a model that ignored it and called a different DECLARED function
      // produced a call that validated cleanly and ran the wrong thing.
      final pinned =
          allowedNames(_funcs, const ToolChoice.function('get_weather'));

      expect(parse('{"name":"send_email","arguments":{"to":"a@b.c"}}', pinned),
          isNull);
      expect(
          parse('{"name":"get_weather","arguments":{"city":"Lima"}}', pinned),
          isNotNull);
    });

    test('pinning a function nobody declared authorises nothing', () {
      expect(allowedNames(_funcs, const ToolChoice.function('nope')), isEmpty);
    });
  });

  group('coverage — the dialects a prompted model actually emits', () {
    const dialects = <String, String>{
      'bare JSON': '{"name":"get_weather","arguments":{"city":"Lima"}}',
      'fenced':
          '```json\n{"name":"get_weather","arguments":{"city":"Lima"}}\n```',
      'tagged':
          '<tool_call>{"name":"get_weather","arguments":{"city":"Lima"}}</tool_call>',
      'Mistral marker':
          '[TOOL_CALLS][{"name":"get_weather","arguments":{"city":"Lima"}}]',
      'Python literal':
          "{'name': 'get_weather', 'arguments': {'city': 'Lima'}}",
      'Anthropic input': '{"name":"get_weather","input":{"city":"Lima"}}',
      'parameters key': '{"name":"get_weather","parameters":{"city":"Lima"}}',
      'ReAct': '{"action":"get_weather","action_input":{"city":"Lima"}}',
      'ReAct sibling': '{"tool":"get_weather","tool_input":{"city":"Lima"}}',
      'legacy function_call':
          '{"function_call":{"name":"get_weather","arguments":"{\\"city\\":\\"Lima\\"}"}}',
      'tool_use wrapper':
          '{"tool_use":{"name":"get_weather","arguments":{"city":"Lima"}}}',
      'response shape':
          '{"tool_calls":[{"name":"get_weather","arguments":{"city":"Lima"}}]}',
      'leaked namespace':
          '{"name":"functions.get_weather","arguments":{"city":"Lima"}}',
      'wrong case': '{"name":"GET_WEATHER","arguments":{"city":"Lima"}}',
      'trailing comma': '{"name":"get_weather","arguments":{"city":"Lima",}}',
    };

    dialects.forEach((label, text) {
      test('$label reads as the same call', () {
        final calls = parse(text);
        expect(calls, hasLength(1), reason: text);
        expect(calls!.single.name, 'get_weather');
        expect(calls.single.arguments, {'city': 'Lima'});
      });
    });

    test('a zero-argument call needs no arguments key', () {
      expect(parse('{"name":"get_weather"}')!.single.arguments, isEmpty);
    });

    test('malformed argument JSON keeps the call with empty arguments', () {
      // The name is valid and the model clearly meant to call. A call the app
      // can reject beats prose it will misread as an answer.
      expect(
          parse('{"name":"get_weather","arguments":"{not json"}')!
              .single
              .arguments,
          isEmpty);
    });

    test('one tag per parallel call', () {
      const text =
          '<tool_call>{"name":"get_weather","arguments":{"city":"Lima"}}</tool_call>'
          '<tool_call>{"name":"get_weather","arguments":{"city":"Quito"}}</tool_call>';
      expect(parse(text)!.map((c) => c.arguments['city']), ['Lima', 'Quito']);
    });

    test('JSONL-style adjacent objects batch', () {
      const text = '{"name":"get_weather","arguments":{"city":"Lima"}}\n'
          '{"name":"get_weather","arguments":{"city":"Quito"}}';
      expect(parse(text)!.map((c) => c.arguments['city']), ['Lima', 'Quito']);
    });

    test('a case-ambiguous name names neither', () {
      // Two declared names differing only by case make a third spelling
      // ambiguous, so it stays text.
      expect(
          detectToolCalls(
              '{"name":"RUN","arguments":{}}', const {'Run', 'run'}),
          isNull);
    });
  });

  group('where the false positives live', () {
    test('a mixed array of calls and data is data', () {
      const text = '[{"name":"get_weather","arguments":{"city":"Lima"}},'
          ' {"temperature": 21}]';
      expect(parse(text), isNull);
    });

    test('a schema quoted inside a clarifying question is not a call', () {
      const text = 'Its schema is {"name": "get_weather"}, but which city did '
          'you mean? I can look up several if you tell me which ones you care '
          'about, since the function takes one city at a time.';
      expect(parse(text), isNull);
    });

    test('the real call wins over an illustrative example', () {
      const text = 'Here is how I would call it:\n'
          '```json\n{"name":"get_weather","arguments":{"city":"EXAMPLE"}}\n```\n'
          'Now the real call: {"name":"get_weather","arguments":{"city":"Lima"}}';
      expect(parse(text)!.single.arguments['city'], 'Lima');
    });

    test('a draft inside a reasoning block is not the answer', () {
      const text =
          '<think>{"name":"send_email","arguments":{"to":"draft@x.com"}}</think>'
          '{"name":"get_weather","arguments":{"city":"Lima"}}';
      expect(parse(text)!.single.name, 'get_weather');
    });

    test('an unclosed reasoning block is scratchpad to the end', () {
      expect(
          parse('<think>maybe {"name":"get_weather","arguments":{}}'), isNull);
    });

    test('braces inside string values do not close the object', () {
      const text = '{"name":"get_weather","arguments":{"city":"Lima } Peru"}}';
      expect(parse(text)!.single.arguments['city'], 'Lima } Peru');
    });
  });

  group('argument repair — lossless or identity', () {
    test('a stringified integer is re-read as one', () {
      // This is the round trip the repair pass used to cost.
      final calls = parse(
          '{"name":"get_weather","arguments":{"city":"Lima","days":"5"}}');
      expect(calls!.single.arguments['days'], 5);
    });

    test('a number spelling JSON does not allow stays a string', () {
      final calls = parse(
          '{"name":"get_weather","arguments":{"city":"Lima","days":"1_000"}}');
      expect(calls!.single.arguments['days'], '1_000');
    });

    test('a whole double folds to the canonical integer', () {
      expect(coerceValue(5.0, const {'type': 'integer'}), 5);
    });

    test('a union leaves an already-satisfying value alone', () {
      // "5" under ["integer", "string"] IS the string.
      expect(
          coerceValue('5', const {
            'type': ['integer', 'string']
          }),
          '5');
    });

    test('a unique case-insensitive enum value is repaired', () {
      final calls = parse(
          '{"name":"get_weather","arguments":{"city":"Lima","unit":"Celsius"}}');
      expect(calls!.single.arguments['unit'], 'celsius');
    });

    test('repair recurses into nested objects and array items', () {
      const schema = {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'qty': {'type': 'integer'},
              },
            },
          },
        },
      };
      expect(
          coerceValue({
            'items': [
              {'qty': '2'},
              {'qty': '3'},
            ],
          }, schema),
          {
            'items': [
              {'qty': 2},
              {'qty': 3},
            ],
          });
    });

    test('an undeclared parameter is never touched', () {
      final calls = parse(
          '{"name":"get_weather","arguments":{"city":"Lima","extra":"7"}}');
      expect(calls!.single.arguments['extra'], '7');
    });

    test('a boolean is not folded into a number', () {
      // Folding true into 1 would rewrite a flag the model may have meant.
      expect(coerceValue(true, const {'type': 'integer'}), isTrue);
    });

    test('repair is idempotent', () {
      const schema = {
        'type': 'object',
        'properties': {
          'days': {'type': 'integer'},
        },
      };
      final once = coerceValue({'days': '5'}, schema);
      expect(coerceValue(once, schema), once);
    });
  });

  group('totality', () {
    const junk = [
      '',
      '   ',
      '{',
      '}}}}}}}}}}',
      '[[[[[[[[[[',
      '{"name":',
      '{"name":"get_weather","arguments":',
      '<think><think><think>',
      '``````',
      '[TOOL_CALLS][TOOL_CALLS]',
    ];

    for (final input in junk) {
      test(
          'never raises and never escapes the allow-list: ${input.length} chars',
          () {
        final out = parse(input);
        expect(
            out == null || out.every((c) => _names.contains(c.name)), isTrue);
      });
    }

    test('a storm of unclosed openers gives up in the safe direction', () {
      // Bounded work: a missed call, never an invented one, and never O(n²).
      final text =
          '${'{' * 10000}{"name":"get_weather","arguments":{"city":"Lima"}}';
      final out = parse(text);
      expect(out == null || out.single.name == 'get_weather', isTrue);
    });
  });

  group('the tolerant reader', () {
    test('reads ordinary JSON unchanged', () {
      expect(loadsTolerant('{"a": 1}'), {'a': 1});
    });

    test('reads the Python-literal dialect', () {
      expect(loadsTolerant("{'a': True, 'b': None, 'c': False}"),
          {'a': true, 'b': null, 'c': false});
    });

    test('leaves keywords inside strings alone', () {
      // A rewrite that ignored quoting would turn this value into a boolean.
      expect(loadsTolerant("{'a': 'True'}"), {'a': 'True'});
    });

    test('does not rewrite a keyword that is part of a longer word', () {
      expect(loadsTolerant("{'a': 'NoneOfTheAbove'}"), {'a': 'NoneOfTheAbove'});
    });

    test('a brace inside a single-quoted string does not end the object', () {
      expect(
          loadsTolerant("{'q': 'use } carefully'}"), {'q': 'use } carefully'});
    });

    test('returns null rather than throwing on nonsense', () {
      expect(loadsTolerant('not json at all {{{'), isNull);
    });
  });

  group('how it composes with our own markers', () {
    test('a reply in another dialect no longer costs a repair', () {
      // No marker, no {"calls": …} envelope — just the call, in a shape the
      // model was never asked for. This used to come back unreadable and spend
      // a second upstream message.
      final envelope = parseToolEnvelope(
        '```json\n{"name":"get_weather","arguments":{"city":"Lima"}}\n```',
        _names,
        functions: _funcs,
      );

      expect(
          (envelope as EnvelopeCalls).calls.single.arguments['city'], 'Lima');
      expect(envelope.notes, contains('dialect'));
    });

    test('the documented envelope is still the fast path', () {
      final envelope = parseToolEnvelope(
        '$kToolCallMarker{"calls":[{"name":"get_weather",'
        '"arguments":{"city":"Lima"}}]}',
        _names,
        functions: _funcs,
      );

      expect((envelope as EnvelopeCalls).calls.single.name, 'get_weather');
      expect(envelope.notes, isNot(contains('dialect')));
    });

    test('our markers still decide outright', () {
      expect((parseToolEnvelope(kNoToolMarker, _names) as EnvelopeCalls).calls,
          isEmpty);
      final needInfo = parseToolEnvelope(
          '$kNeedInfoMarker{"function":"send_email","missing":["to"]}', _names);
      expect((needInfo as EnvelopeNeedInfo).missing, ['to']);
    });
  });
}
