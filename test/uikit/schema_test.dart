import 'dart:convert';

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/ui_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a small screen with state and actions', () {
    final spec = UiSpec.fromJson(jsonDecode('''
      {
        "title": "Calculator",
        "state": {"display": "0"},
        "root": {
          "type": "column",
          "gap": 8,
          "children": [
            {"type": "text", "text": "{{display}}", "fontSize": 32},
            {"type": "button", "text": "7",
             "actions": [{"type": "append", "key": "display", "value": "7"}]}
          ]
        }
      }
    '''));

    expect(spec.title, 'Calculator');
    expect(spec.state['display'], '0');
    expect(spec.root.type, 'column');
    expect(spec.root.children, hasLength(2));
    expect(spec.root.children.last.actions.single.type, 'append');
  });

  test('coerces non-string state values, which models emit freely', () {
    final spec = UiSpec.fromJson(jsonDecode('''
      {"state": {"n": 0}, "root": {"type": "text", "text": "{{n}}"}}
    '''));
    expect(spec.state['n'], '0');
  });

  test('rejects an unknown node type instead of guessing', () {
    // A half-understood interface is worse than one that refuses to render.
    expect(
      () => UiSpec.fromJson(jsonDecode('{"root":{"type":"Carousel"}}')),
      throwsA(isA<ProtocolException>()
          .having((e) => e.message, 'message', contains('Carousel'))),
    );
  });

  test('rejects an unknown action, and names what is supported', () {
    expect(
      () => UiSpec.fromJson(jsonDecode('''
        {"root":{"type":"button","actions":[{"type":"http","key":"x"}]}}
      ''')),
      throwsA(isA<ProtocolException>()
          .having((e) => e.message, 'message', contains('calc'))),
    );
  });

  test('rejects a spec with no root', () {
    expect(() => UiSpec.fromJson(jsonDecode('{"state":{}}')),
        throwsA(isA<ProtocolException>()));
  });

  group('resolveBindings', () {
    test('substitutes declared keys', () {
      expect(resolveBindings('= {{a}}!', {'a': '7'}), '= 7!');
    });

    test('renders an undeclared key as blank rather than failing', () {
      expect(resolveBindings('x{{nope}}y', const {}), 'xy');
    });
  });
}
