import 'dart:convert';

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/src/core/api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  test('models() parses capabilities, not just ids', () async {
    final transport = FakeTransport()
      ..getResponse = jsonEncode({
        'models': [
          {
            'slug': 'gpt-5-6',
            'title': 'GPT-5.6 Luna',
            'max_tokens': 34834,
            'reasoning_type': 'auto',
            'enabled_tools': ['search', 'canvas'],
          }
        ]
      });
    final client = ChatGptClient(transport: transport);

    final models = await client.models();

    expect(models.single.id, 'gpt-5-6');
    expect(models.single.title, 'GPT-5.6 Luna');
    expect(models.single.contextWindow, 34834);
    expect(models.single.reasoningType, 'auto');
    expect(models.single.enabledTools, ['search', 'canvas']);
  });

  test('limits() reports remaining counts and blocked features', () async {
    final transport = FakeTransport()
      ..getResponse = jsonEncode({
        'limits_progress': [
          {'feature_name': 'file_upload', 'remaining': 3}
        ],
        'model_limits': [
          {'model_slug': 'gpt-5-6'}
        ],
        'blocked_features': [
          {'name': 'image_gen'}
        ],
      });
    final client = ChatGptClient(transport: transport);

    final limits = await client.limits();

    expect(limits.remaining['file_upload'], 3);
    expect(limits.cappedModels, ['gpt-5-6']);
    expect(limits.blockedFeatures, ['image_gen']);
  });

  test('translate() returns the translated text', () async {
    final transport = FakeTransport()
      ..getResponse = jsonEncode({'translation': 'hello world'});
    final client = ChatGptClient(transport: transport);

    expect(await client.translate('hola mundo', target: 'en'), 'hello world');
  });

  // Fix round 1 — the parsers must raise ChatGptException's ProtocolException
  // for anything they cannot make sense of, never a raw dart:convert or
  // type-cast exception, so a consumer can catch one sealed family. See
  // task-11-report.md, "Fix round 1" section, for the absent-vs-malformed
  // rule these tests encode.

  group('parseModels rejects malformed bodies with ProtocolException', () {
    test('empty body', () {
      expect(() => parseModels(''), throwsA(isA<ProtocolException>()));
    });

    test('non-JSON body (e.g. a proxy error page)', () {
      expect(() => parseModels('<html>502 Bad Gateway</html>'),
          throwsA(isA<ProtocolException>()));
    });

    test('a top-level value that is not a JSON object', () {
      expect(() => parseModels(jsonEncode([1, 2, 3])),
          throwsA(isA<ProtocolException>()));
    });

    test('"models" present with the wrong shape', () {
      expect(() => parseModels(jsonEncode({'models': 'not-a-list'})),
          throwsA(isA<ProtocolException>()));
    });
  });

  group('parseModels accepts well-formed-but-empty bodies', () {
    test('an absent "models" field yields an empty list', () {
      expect(parseModels(jsonEncode(<String, dynamic>{})), isEmpty);
    });

    test('an empty "models" list yields an empty list', () {
      expect(parseModels(jsonEncode({'models': <dynamic>[]})), isEmpty);
    });
  });

  group('parseLimits rejects malformed bodies with ProtocolException', () {
    test('empty body', () {
      expect(() => parseLimits(''), throwsA(isA<ProtocolException>()));
    });

    test('non-JSON body (e.g. a proxy error page)', () {
      expect(() => parseLimits('<html>502 Bad Gateway</html>'),
          throwsA(isA<ProtocolException>()));
    });

    test('a top-level value that is not a JSON object', () {
      expect(() => parseLimits(jsonEncode([1, 2, 3])),
          throwsA(isA<ProtocolException>()));
    });

    test('"limits_progress" present with the wrong shape', () {
      expect(() => parseLimits(jsonEncode({'limits_progress': 'not-a-list'})),
          throwsA(isA<ProtocolException>()));
    });
  });

  test('parseLimits accepts a well-formed-but-empty body', () {
    final limits = parseLimits(jsonEncode(<String, dynamic>{}));
    expect(limits.remaining, isEmpty);
    expect(limits.cappedModels, isEmpty);
    expect(limits.blockedFeatures, isEmpty);
  });

  group('parseTranslation rejects malformed bodies with ProtocolException', () {
    test('empty body', () {
      expect(() => parseTranslation(''), throwsA(isA<ProtocolException>()));
    });

    test('non-JSON body (e.g. a proxy error page)', () {
      expect(() => parseTranslation('<html>502 Bad Gateway</html>'),
          throwsA(isA<ProtocolException>()));
    });

    test('a top-level value that is not a JSON object', () {
      expect(() => parseTranslation(jsonEncode([1, 2, 3])),
          throwsA(isA<ProtocolException>()));
    });
  });

  test('parseTranslation accepts a well-formed body missing every known key',
      () {
    expect(parseTranslation(jsonEncode(<String, dynamic>{})), '');
  });
}
