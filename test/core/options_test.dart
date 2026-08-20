import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enums map to the exact strings the backend validates', () {
    expect(ThinkingEffort.standard.wire, 'standard');
    expect(ThinkingEffort.extended.wire, 'extended');
    expect(ThinkingEffort.max.wire, 'max');
    expect(ServiceTier.standard.wire, 'standard');
    expect(ServiceTier.priority.wire, 'priority');

    for (final e in ThinkingEffort.values) {
      expect(kThinkingEfforts, contains(e.wire));
    }
    for (final t in ServiceTier.values) {
      expect(kServiceTiers, contains(t.wire));
    }
  });

  test('validate accepts a well-formed options object', () {
    expect(
      () => const SendOptions(thinkingEffort: ThinkingEffort.max).validate(),
      returnsNormally,
    );
  });

  test('validate rejects an empty model before any request is made', () {
    expect(
      () => const SendOptions(model: '').validate(),
      throwsA(isA<InvalidRequestException>()
          .having((e) => e.field, 'field', 'model')),
    );
  });

  test('events are exhaustively switchable', () {
    const events = <ChatEvent>[
      TextDelta('hola'),
      SearchStarted(['q']),
      CitationsReceived([]),
      GenuiWidgetEvent('weather', {}),
      CanvasDocument(markdown: '# doc'),
      ImageGenerated('https://x/y.png'),
      ModelDowngraded(requested: 'gpt-5-6', actual: 'gpt-5-6-mini'),
      QuotaRotated('hourly limit'),
      TurnCompleted(actualModel: 'gpt-5-6', finishReason: 'stop'),
    ];

    final kinds = events.map((e) => switch (e) {
          TextDelta() => 'text',
          SearchStarted() => 'search',
          CitationsReceived() => 'cites',
          GenuiWidgetEvent() => 'widget',
          CanvasDocument() => 'canvas',
          ImageGenerated() => 'image',
          ModelDowngraded() => 'downgrade',
          QuotaRotated() => 'rotated',
          TurnCompleted() => 'done',
        });

    expect(kinds.length, 9);
    expect(kinds, contains('downgrade'));
  });

  // Fix round 1, Finding 1: copyWith is the safe way to extend an existing
  // SendOptions for one field, so a per-turn override never has to fall
  // back to a bare `SendOptions(...)` literal — which would silently reset
  // `model` to 'auto'.

  group('copyWith', () {
    test('preserves every unspecified field', () {
      const base = SendOptions(
        model: 'gpt-5-6',
        webSearch: true,
        tools: true,
        canvas: false,
        jsonMode: true,
        thinkingEffort: ThinkingEffort.extended,
        serviceTier: ServiceTier.priority,
      );

      final copy = base.copyWith(canvas: true);

      expect(copy.model, 'gpt-5-6');
      expect(copy.webSearch, true);
      expect(copy.tools, true);
      expect(copy.canvas, true); // the one field actually changed
      expect(copy.jsonMode, true);
      expect(copy.thinkingEffort, ThinkingEffort.extended);
      expect(copy.serviceTier, ServiceTier.priority);
    });

    test('replaces exactly the fields given, leaving the rest untouched',
        () {
      const base = SendOptions(model: 'auto');

      final copy = base.copyWith(
        model: 'gpt-5-5',
        webSearch: false,
        jsonMode: true,
      );

      expect(copy.model, 'gpt-5-5');
      expect(copy.webSearch, false);
      expect(copy.jsonMode, true);
      expect(copy.canvas, isNull);
      expect(copy.tools, isNull);
      expect(copy.thinkingEffort, isNull);
      expect(copy.serviceTier, isNull);
    });

    test('called with no arguments returns an equivalent copy', () {
      const base = SendOptions(model: 'gpt-5-6-mini', webSearch: true);

      final copy = base.copyWith();

      expect(copy.model, base.model);
      expect(copy.webSearch, base.webSearch);
    });
  });
}
