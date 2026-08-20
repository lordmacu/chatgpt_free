import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Walks a bubble's rendered spans and returns the runs that carry [weight].
List<String> _runsWithWeight(WidgetTester tester, FontWeight weight) {
  final rich = tester.widget<SelectableText>(find.byType(SelectableText));
  final out = <String>[];
  rich.textSpan!.visitChildren((span) {
    if (span is TextSpan &&
        span.text != null &&
        span.style?.fontWeight == weight) {
      out.add(span.text!);
    }
    return true;
  });
  return out;
}

Widget _bubble(String text) => MaterialApp(
      home: Scaffold(
        body: MessageBubble(message: ChatMessage(role: 'assistant', text: text)),
      ),
    );

void main() {
  testWidgets('renders **bold** as weight, not literal asterisks',
      (tester) async {
    // Regression, found by installing the demo on a phone: the reply
    // "Tu nombre es **Cristian**." showed the asterisks to the user.
    await tester.pumpWidget(_bubble('Tu nombre es **Cristian**.'));

    expect(find.textContaining('**'), findsNothing);
    expect(_runsWithWeight(tester, FontWeight.bold), contains('Cristian'));
  });

  testWidgets('renders *italic* and `code` without their markers',
      (tester) async {
    await tester.pumpWidget(_bubble('un *matiz* y un `identificador`'));

    expect(find.textContaining('*'), findsNothing);
    expect(find.textContaining('`'), findsNothing);
  });

  testWidgets('a heading line becomes bold, keeping its text', (tester) async {
    await tester.pumpWidget(_bubble('## Resumen'));

    expect(find.textContaining('#'), findsNothing);
    expect(_runsWithWeight(tester, FontWeight.bold), contains('Resumen'));
  });

  testWidgets('plain text survives untouched', (tester) async {
    await tester.pumpWidget(_bubble('sin formato alguno'));

    expect(find.textContaining('sin formato alguno'), findsOneWidget);
  });

  testWidgets('an unmatched asterisk is left alone rather than eaten',
      (tester) async {
    await tester.pumpWidget(_bubble('2 * 3 = 6'));

    expect(find.textContaining('2 * 3 = 6'), findsOneWidget);
  });
}
