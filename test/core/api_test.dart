import 'dart:convert';

import 'package:chatgpt_free/src/core/client.dart';
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
}
