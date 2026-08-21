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
    final events = await parser.parse(framesOf('plain_text')).toList();

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

  test(
      'web search: emits SearchStarted with the real queries '
      '(Final review, Blocker 2)', () async {
    // Regression: _handleControl's 'url_moderation' case read event['url'],
    // but real frames (web_search.sse lines 70/78) carry the URL nested at
    // url_moderation_result.full_url and have no top-level 'url' key —
    // parsing this fixture used to yield zero SearchStarted events. The
    // real queries sit at message.metadata.search_model_queries.queries on
    // the web.run tool message (web_search.sse line 38).
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('web_search')).toList();

    final started = events.whereType<SearchStarted>().toList();
    expect(started, hasLength(1));
    expect(
      started.single.queries,
      containsAll(<String>[
        'capital of Mongolia Ulaanbaatar official',
        'Mongolia capital Ulaanbaatar Britannica',
      ]),
    );
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
      const SseFrame(
          'delta',
          '{"p":"","o":"add","v":{"message":{"content":'
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

  test('recovers cleanly when a PUA marker is split across two SSE chunks',
      () async {
    // Regression for fix round 1, finding 1: the open half of a structured
    // marker (\ue200cite\ue202turn0search0) lands in one delta, the close
    // half (\ue201) in the next. Between those two frames the marker is
    // incomplete, so stripPuaMarkers can only remove the stray control
    // characters — the kind/ref payload sits in plain text until the
    // marker closes. A naive length-diff over that intermediate state
    // treats the payload as already-emitted, then the cleaned text
    // *shrinks* once the marker completes, permanently desyncing the
    // cursor and silently dropping everything appended after that point.
    final parser = TurnParser(requestedModel: 'auto');
    final frames = Stream.fromIterable([
      const SseFrame(
          'delta',
          '{"p":"","o":"add","v":{"message":{"content":'
              '{"parts":[""]},"metadata":{}}}}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"append","v":'
              '"hello \\ue200cite\\ue202turn0search0"}'),
      const SseFrame('delta', '{"v":"\\ue201 world"}'),
      const SseFrame('delta', '{"v":" more text after"}'),
    ]);

    final events = await parser.parse(frames).toList();
    final text = events.whereType<TextDelta>().map((e) => e.text).join();

    expect(text, 'hello  world more text after');
    expect(text, isNot(contains('cite')));
    expect(text, isNot(contains('turn0search0')));
    expect(text.codeUnits.any((c) => c >= 0xE000 && c <= 0xF8FF), isFalse);
  });

  test(
      'emits CitationsReceived again when an existing citation changes '
      'in place', () async {
    // Regression for fix round 1, finding 2: web_search.sse line 81 patches
    // citation 0's attribution without changing the citation count — the
    // bug (comparing list length only) masks this in the fixture only
    // because that same patch also happens to append a second citation.
    // This drives the in-place change in isolation, with the count held
    // at one throughout, so a length-only comparison cannot see it.
    final parser = TurnParser(requestedModel: 'auto');
    final frames = Stream.fromIterable([
      const SseFrame(
          'delta',
          '{"p":"","o":"add","v":{"message":{"content":{"parts":[""]},'
              '"metadata":{"content_references":[{"items":[{"title":'
              '"Old Title","url":"https://example.com/a",'
              '"attribution":"Old Attribution"}]}]}}}}'),
      const SseFrame(
          'delta',
          '{"p":"/message/metadata/content_references/0/items/0/title",'
              '"o":"replace","v":"New Title"}'),
    ]);

    final events = await parser.parse(frames).toList();
    final receipts = events.whereType<CitationsReceived>().toList();

    expect(receipts, hasLength(2));
    expect(receipts.first.citations.single.title, 'Old Title');
    expect(receipts.last.citations.single.title, 'New Title');
  });

  test(
      'ModelDowngraded and actualModel reflect the assistant model, not '
      'the echoed user message', () async {
    // Regression for fix round 1, finding 3: _rawText was gated on
    // author.role to stop the user's echoed prompt leaking into the reply
    // text, but _emitDowngrade read model_slug/resolved_model_slug from
    // whichever message currently occupied the shared document slot with
    // no such gate. Here the user-echo message and the assistant message
    // carry different, deliberately distinct slugs, none equal to each
    // other, so a downgrade decision made from the wrong message is
    // directly observable.
    final parser = TurnParser(requestedModel: 'requested-model-x');
    final frames = Stream.fromIterable([
      const SseFrame(
          'delta',
          '{"p":"","o":"add","v":{"message":{"author":{"role":"user"},'
              '"content":{"parts":["hi"]},"metadata":{"resolved_model_slug":'
              '"user-side-bogus-model"}}}}'),
      const SseFrame(
          'delta',
          '{"v":{"message":{"author":{"role":"assistant"},"content":'
              '{"parts":[""]},"metadata":{"model_slug":'
              '"assistant-real-model"}}}}'),
    ]);

    final events = await parser.parse(frames).toList();
    final done = events.whereType<TurnCompleted>().single;
    final downgrades = events.whereType<ModelDowngraded>().toList();

    expect(done.actualModel, 'assistant-real-model');
    expect(downgrades, hasLength(1));
    expect(downgrades.single.actual, 'assistant-real-model');
  });

  // Fix round 2: DeltaApplier's `replace` and `truncate` are not scoped
  // away from the text channel — they are first-class operations the
  // backend can send on /message/content/parts/0 at any point, the same as
  // the Python reference this package ports (chatgpt_client.py:685-688).
  // A consumer that folds every TextDelta — starting from '', replacing
  // its running text with .text when .isReset is true and appending it
  // otherwise — must end the turn holding exactly the text the backend
  // ended it with. This is the "consumer reconstruction" every test below
  // performs; it is not plain String.join(), because once a reset can
  // happen, plain concatenation of every .text is no longer well-defined
  // as "the text so far".
  String reconstruct(Iterable<TextDelta> deltas) {
    var text = '';
    for (final d in deltas) {
      text = d.isReset ? d.text : text + d.text;
    }
    return text;
  }

  test(
      'a replace that shortens the reply mid-stream resyncs instead of '
      'freezing', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final frames = Stream.fromIterable([
      const SseFrame(
          'delta',
          '{"p":"","o":"add","v":{"message":{"content":'
              '{"parts":[""]},"metadata":{}}}}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"append","v":'
              '"This is a much longer draft that will be replaced"}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"replace","v":'
              '"Short answer"}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"append","v":'
              '", now finalized."}'),
    ]);

    final events = await parser.parse(frames).toList();
    final deltas = events.whereType<TextDelta>().toList();

    expect(reconstruct(deltas), 'Short answer, now finalized.');
  });

  test(
      'a truncate that shortens the reply mid-stream resyncs instead of '
      'freezing', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final frames = Stream.fromIterable([
      const SseFrame(
          'delta',
          '{"p":"","o":"add","v":{"message":{"content":'
              '{"parts":[""]},"metadata":{}}}}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"append","v":'
              '"Hello wonderful world"}'),
      const SseFrame(
          'delta', '{"p":"/message/content/parts/0","o":"truncate","v":5}'),
      const SseFrame(
          'delta',
          '{"p":"/message/content/parts/0","o":"append","v":'
              '" there, everyone!"}'),
    ]);

    final events = await parser.parse(frames).toList();
    final deltas = events.whereType<TextDelta>().toList();

    expect(reconstruct(deltas), 'Hello there, everyone!');
  });

  test('reports the title the backend generates for the conversation',
      () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('plain_text')).toList();

    expect(events.whereType<ConversationTitled>().single.title,
        'Decir hola mundo');
    expect(parser.title, 'Decir hola mundo');
  });

  test('the backend refines the title mid-turn; the last one wins', () async {
    // canvas.sse carries two title_generation frames, captured from real
    // traffic: a first guess and the title the backend settled on.
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser.parse(framesOf('canvas')).toList();

    final titles = events.whereType<ConversationTitled>().map((e) => e.title);
    expect(titles, ['Escribir documento sobre mar', 'Escribir sobre el mar']);
    expect(parser.title, 'Escribir sobre el mar');
  });

  test('a turn with no title frame leaves the title unset', () async {
    final parser = TurnParser(requestedModel: 'auto');
    final events = await parser
        .parse(Stream.value(const SseFrame(null, '{"v":"hola","p":""}')))
        .toList();

    expect(events.whereType<ConversationTitled>(), isEmpty);
    expect(parser.title, isNull);
  });

  test('the inline quota snapshot carries when each feature resets', () async {
    final parser = TurnParser(requestedModel: 'auto');
    await parser.parse(framesOf('plain_text')).drain<void>();

    // "0 left" is not actionable on its own — a UI has to be able to say when
    // it comes back.
    expect(parser.limits!.resetAfter['file_upload'],
        DateTime.parse('2026-08-21T16:12:28.014904Z'));
    expect(
        parser.limits!.resetAfter['dictation']!
            .isAfter(DateTime.utc(2026, 8, 26)),
        isTrue);
  });
}
