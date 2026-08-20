import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractJson', () {
    test('unwraps a fenced block with a language tag', () {
      // This is what the backend actually returns — seen on device.
      const reply = '```json\n{"a": 1}\n```';
      expect(extractJson(reply), '{"a": 1}');
    });

    test('unwraps a fence with no language tag', () {
      expect(extractJson('```\n[1, 2]\n```'), '[1, 2]');
    });

    test('finds JSON surrounded by prose', () {
      const reply = 'Aquí tienes:\n{"a": 1}\nEspero que sirva.';
      expect(extractJson(reply), '{"a": 1}');
    });

    test('leaves bare JSON alone', () {
      expect(extractJson('{"a": 1}'), '{"a": 1}');
    });

    test('returns the text unchanged when there is no JSON', () {
      expect(extractJson('lo siento, no puedo'), 'lo siento, no puedo');
    });
  });

  group('decodeJsonReply', () {
    test('decodes a fenced object', () {
      final decoded = decodeJsonReply('```json\n{"n": 7}\n```');
      expect((decoded! as Map)['n'], 7);
    });

    test('throws ProtocolException on a non-JSON reply', () {
      expect(
        () => decodeJsonReply('no es json'),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}
