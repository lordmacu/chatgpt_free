@Tags(['live'])
library;

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a real turn streams real text', () async {
    final client = ChatGptClient();
    final session = client.newSession();

    final events = await client
        .sendWithRotation(session, 'Reply with exactly: OK')
        .toList();

    final text = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(text.trim(), isNotEmpty);
    expect(events.whereType<TurnCompleted>().single.actualModel, isNotEmpty);

    client.close();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('the model list is non-empty and carries capabilities', () async {
    final client = ChatGptClient();
    final models = await client.models();

    expect(models, isNotEmpty);
    expect(models.first.contextWindow, isNotNull);

    client.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('limits reports the anonymous ceilings', () async {
    final client = ChatGptClient();
    final limits = await client.limits();

    expect(limits.remaining, isNotEmpty);

    client.close();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
