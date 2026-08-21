import 'package:chatgpt_free/tools.dart';
import 'package:flutter_test/flutter_test.dart';

const FunctionTool _weather = FunctionTool(
  name: 'get_weather',
  parameters: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
      'units': {
        'type': 'string',
        'enum': ['c', 'f'],
      },
    },
    'required': ['city'],
  },
);

/// Three levels of nesting, an array of objects, a boolean and an enum — the
/// shape the measured 42-of-42 structural pass rate was measured against.
const FunctionTool _booking = FunctionTool(
  name: 'book',
  parameters: {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'trip': {
        'type': 'object',
        'properties': {
          'legs': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'from': {'type': 'string'},
                'to': {'type': 'string'},
                'seats': {'type': 'integer'},
              },
              'required': ['from', 'to'],
            },
          },
          'refundable': {'type': 'boolean'},
        },
        'required': ['legs'],
      },
    },
    'required': ['trip'],
  },
);

List<String> check(String name, Map<String, dynamic> args,
        [List<FunctionTool> tools = const [_weather, _booking]]) =>
    validateToolCalls([ToolCall(name: name, arguments: args)], tools);

void main() {
  test('a valid call produces no errors', () {
    expect(check('get_weather', {'city': 'Lima', 'units': 'c'}), isEmpty);
  });

  test('a missing required parameter is reported by name', () {
    expect(check('get_weather', {'units': 'c'}),
        ['get_weather: city: missing required']);
  });

  test('a wrong type is reported at its path', () {
    expect(check('get_weather', {'city': 42}),
        ['get_weather: city: expected string']);
  });

  test('a value outside an enum is reported', () {
    expect(check('get_weather', {'city': 'Lima', 'units': 'kelvin'}),
        ['get_weather: units: kelvin not in enum']);
  });

  test('a function nobody declared is reported, not silently accepted', () {
    expect(check('launch_missiles', const {}),
        ['unknown function "launch_missiles"']);
  });

  test('checks all the way down an array of nested objects', () {
    final errors = check('book', {
      'trip': {
        'legs': [
          {'from': 'BOG', 'to': 'LIM', 'seats': 2},
          {'from': 'LIM'}, // no "to"
        ],
        'refundable': true,
      },
    });

    expect(errors, ['book: trip/legs/1/to: missing required']);
  });

  test('a wrong type deep in an array names the index', () {
    final errors = check('book', {
      'trip': {
        'legs': [
          {'from': 'BOG', 'to': 'LIM', 'seats': 'two'},
        ],
      },
    });

    expect(errors, ['book: trip/legs/0/seats: expected integer']);
  });

  test('additionalProperties: false rejects an invented parameter', () {
    final errors = check('book', {
      'trip': {'legs': <Object>[]},
      'discount': '50%',
    });

    expect(errors, ['book: discount: not allowed']);
  });

  test('a wrong type stops the walk instead of cascading', () {
    // One mistake, one error: reporting the missing children of something
    // that is not an object at all would bury the real cause.
    expect(check('book', {'trip': 'BOG-LIM'}), ['book: trip: expected object']);
  });

  test('a schema keyword this does not implement is ignored, not failed', () {
    // Rejecting a valid call is worse here than passing an unusual one.
    const tool = FunctionTool(
      name: 'search',
      parameters: {
        'type': 'object',
        'properties': {
          'q': {'type': 'string', 'minLength': 3, 'pattern': '^[a-z]+\$'},
        },
      },
    );

    expect(check('search', {'q': 'a'}, const [tool]), isEmpty);
  });

  test('a zero-parameter function validates with empty arguments', () {
    const tool = FunctionTool(name: 'now');
    expect(check('now', const {}, const [tool]), isEmpty);
  });
}
