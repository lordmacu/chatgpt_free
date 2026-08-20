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
}
