import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('MessageBubble renders the message text', (tester) async {
    await tester.pumpWidget(_wrap(const MessageBubble(
      message: ChatMessage(role: 'assistant', text: 'hola mundo'),
    )));

    expect(find.text('hola mundo'), findsOneWidget);
  });

  testWidgets('MessageBubble takes its colours from the theme', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: const Scaffold(
        body: MessageBubble(message: ChatMessage(role: 'user', text: 'x')),
      ),
    ));

    final container = tester.widget<Container>(find
        .descendant(of: find.byType(MessageBubble), matching: find.byType(Container))
        .first);
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, scheme.primaryContainer);
  });

  testWidgets('ChatMessageList renders one bubble per message', (tester) async {
    await tester.pumpWidget(_wrap(const ChatMessageList(messages: [
      ChatMessage(role: 'user', text: 'uno'),
      ChatMessage(role: 'assistant', text: 'dos'),
    ])));

    expect(find.byType(MessageBubble), findsNWidgets(2));
  });

  testWidgets('MessageComposer reports submitted text and clears', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_wrap(MessageComposer(onSend: sent.add)));

    await tester.enterText(find.byType(TextField), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, ['hola']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('MessageComposer is inert while disabled', (tester) async {
    final sent = <String>[];
    await tester
        .pumpWidget(_wrap(MessageComposer(onSend: sent.add, enabled: false)));

    await tester.enterText(find.byType(TextField), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, isEmpty);
  });

  testWidgets('CitationChips renders one chip per source', (tester) async {
    await tester.pumpWidget(_wrap(const CitationChips(citations: [
      Citation(title: 'Fuente A', url: 'https://a.example'),
      Citation(title: 'Fuente B', url: 'https://b.example'),
    ])));

    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(find.text('Fuente A'), findsOneWidget);
  });
}
