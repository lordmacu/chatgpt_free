import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/src/core/request_body.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('includes the fields the backend requires', () {
    final body = buildConversationBody(
      message: 'hola',
      model: 'auto',
      options: const SendOptions(),
    );

    expect(body['action'], 'next');
    expect(body['model'], 'auto');
    expect(body['stream'], isTrue);
    expect(body['force_use_sse'], isTrue);
    expect(body['supported_encodings'], ['v1']);
    expect(body['parent_message_id'], isA<String>());

    final messages = body['messages'] as List;
    final content = (messages.single as Map)['content'] as Map;
    expect(content['parts'], ['hola']);
  });

  test('force_use_search goes on the wire as a boolean, not an enum name', () {
    final body = buildConversationBody(
      message: 'x',
      model: 'auto',
      options: const SendOptions(webSearch: true),
    );

    expect(body['force_use_search'], isA<bool>());
    expect(body['force_use_search'], isTrue);
  });

  test('omits optional fields rather than sending nulls', () {
    final body = buildConversationBody(
      message: 'x',
      model: 'auto',
      options: const SendOptions(),
    );

    expect(body.containsKey('thinking_effort'), isFalse);
    expect(body.containsKey('service_tier'), isFalse);
    expect(body.containsKey('conversation_id'), isFalse);
  });

  test('sends validated effort and tier when given', () {
    final body = buildConversationBody(
      message: 'x',
      model: 'auto',
      options: const SendOptions(
        thinkingEffort: ThinkingEffort.max,
        serviceTier: ServiceTier.priority,
      ),
    );

    expect(body['thinking_effort'], 'max');
    expect(body['service_tier'], 'priority');
  });

  test('never sends sampling parameters — they do not exist in this protocol',
      () {
    final body = buildConversationBody(
      message: 'x',
      model: 'auto',
      options: const SendOptions(),
    );

    for (final banned in [
      'temperature',
      'top_p',
      'max_tokens',
      'presence_penalty',
      'frequency_penalty',
      'seed',
      'n'
    ]) {
      expect(body.containsKey(banned), isFalse,
          reason: '$banned must not be sent');
    }
  });

  test('prepends attachments and the JSON-mode instruction to the prompt', () {
    final body = buildConversationBody(
      message: 'resume',
      model: 'auto',
      options: const SendOptions(jsonMode: true),
      fileTexts: const ['contenido del archivo'],
    );

    final messages = body['messages'] as List;
    final parts = ((messages.single as Map)['content'] as Map)['parts'] as List;
    final prompt = parts.single as String;

    expect(prompt, contains('contenido del archivo'));
    expect(prompt.toLowerCase(), contains('json'));
    expect(prompt, endsWith('resume'));
  });
}
