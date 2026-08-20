import 'dart:io';

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/src/core/sse/reader.dart';
import 'package:chatgpt_free/src/core/sse/turn_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<SseFrame> framesOf(String fixture) =>
    readSse(File('test/fixtures/$fixture.sse').openRead());

void main() {
  test('plain text: assembles the reply and completes', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events =
        await parser.parse(framesOf('plain_text')).toList();

    final text = events.whereType<TextDelta>().map((e) => e.text).join();
    // Equality, not containment: a delta applier that leaks the echoed user
    // prompt into the reply still *contains* 'hola mundo'. That exact bug
    // shipped once and containment did not catch it.
    expect(text.trim(), 'hola mundo');
    expect(text, isNot(contains('Di exactamente')));

    final done = events.whereType<TurnCompleted>().single;
    expect(done.actualModel, 'gpt-5-6');
    expect(parser.conversationId, isNotEmpty);
  });

  test('plain text: reports the quota snapshot carried inline', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('plain_text')).toList();

    final limits = events.whereType<TurnCompleted>().single.limits;
    expect(limits, isNotNull);
    expect(limits!.remaining['file_upload'], isNotNull);
  });

  test('web search: extracts citations with title and url', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('web_search')).toList();

    final citations = events.whereType<CitationsReceived>().last.citations;
    expect(citations, isNotEmpty);
    expect(citations.first.url, startsWith('http'));
    expect(citations.first.title, isNotEmpty);
  });

  test('web search: display text carries no PUA markers', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('web_search')).toList();

    final text = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(text.codeUnits.any((c) => c >= 0xE000 && c <= 0xF8FF), isFalse);
    expect(text, contains('Ulaanbaatar'));
  });

  test('canvas: emits a CanvasDocument from the :::writing block', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('canvas')).toList();

    final doc = events.whereType<CanvasDocument>().single;
    expect(doc.markdown, isNotEmpty);
    expect(doc.markdown, isNot(contains(':::')));
  });

  test('emits ModelDowngraded when the answer came from another model',
      () async {
    final parser = TurnParser(requestedModel: 'gpt-5-6-turbo-imaginary');
    final events = await parser.parse(framesOf('plain_text')).toList();

    final down = events.whereType<ModelDowngraded>().single;
    expect(down.requested, 'gpt-5-6-turbo-imaginary');
    expect(down.actual, 'gpt-5-6');
  });

  test('does not emit ModelDowngraded when auto was requested', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('plain_text')).toList();

    expect(events.whereType<ModelDowngraded>(), isEmpty);
  });

  test('emits GenuiWidgetEvent for a genui marker in the text', () async {
    // No captured fixture contains one, so drive the parser directly.
    final parser = TurnParser(requestedModel: 'auto');
    final frames = Stream.fromIterable([
      const SseFrame('delta', '{"p":"","o":"add","v":{"message":{"content":'
          '{"parts":[""]},"metadata":{}}}}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"append","v":'
          '"antes\\ue200genui\\ue202{\\"name\\":\\"weather\\",'
          '\\"data\\":{\\"c\\":21}}\\ue201después"}'),
    ]);

    final events = await parser.parse(frames).toList();

    final widget = events.whereType<GenuiWidgetEvent>().single;
    expect(widget.name, 'weather');
    expect(widget.data['c'], 21);

    final text = events.whereType<TextDelta>().map((e) => e.text).join();
    expect(text, 'antesdespués');
  });
}
