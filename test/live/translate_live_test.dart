@Tags(['live'])
library;

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

/// The README's Translation section states facts about the live endpoint.
/// These check the ones a reader would act on — a language picker built from
/// that table has to be right, and the demo shipped `pt` and `zh`, which
/// always failed.
void main() {
  test('every language the example offers actually translates', () async {
    final client = ChatGptClient();
    // Mirrors example/lib/translate_screen.dart's kLanguages.
    const codes = [
      'es',
      'en',
      'pt-BR',
      'fr',
      'de',
      'it',
      'ja',
      'zh-CN',
      'ko',
      'ru',
      'ar',
      'hi'
    ];

    final broken = <String>[];
    for (final code in codes) {
      try {
        final out = await client.translate('good morning', target: code);
        if (out.isEmpty) broken.add('$code (empty)');
      } on ChatGptException catch (e) {
        broken.add('$code (${e.message.split('\n').first})');
      }
    }
    client.close();

    expect(broken, isEmpty, reason: 'the picker offers languages that fail');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the codes the README calls rejected really are', () async {
    // If the backend ever starts accepting these, the README is stale and
    // should say so — a table of measured facts has to stay measured.
    final client = ChatGptClient();
    const rejected = ['pt', 'zh', 'en-GB', 'he'];

    final accepted = <String>[];
    for (final code in rejected) {
      try {
        await client.translate('good morning', target: code);
        accepted.add(code);
      } on ChatGptException {
        // Expected.
      }
    }
    client.close();

    expect(accepted, isEmpty,
        reason: 'the README says these are rejected, and they are not');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('source is decorative: a wrong one still translates correctly',
      () async {
    final client = ChatGptClient();
    final out = await client.translate('The quick brown fox',
        target: 'es', source: 'de');
    client.close();

    expect(out.toLowerCase(), contains('zorro'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
