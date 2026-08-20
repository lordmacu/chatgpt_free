import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/ui_schema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A three-key calculator, in the shape a model actually replies with.
UiSpec _calculator() => UiSpec.fromJson(<String, dynamic>{
      'title': 'Calc',
      'state': {'display': '0'},
      'root': {
        'type': 'column',
        'gap': 8,
        'children': [
          {'type': 'text', 'text': '{{display}}', 'fontSize': 32},
          {
            'type': 'grid',
            'columns': 2,
            'children': [
              {
                'type': 'button',
                'text': '7',
                'actions': [
                  {'type': 'append', 'key': 'display', 'value': '7'},
                ],
              },
              {
                'type': 'button',
                'text': '+',
                'actions': [
                  {'type': 'append', 'key': 'display', 'value': '+'},
                ],
              },
              {
                'type': 'button',
                'text': '=',
                'actions': [
                  {'type': 'calc', 'key': 'display', 'expr': '{{display}}'},
                ],
              },
              {
                'type': 'button',
                'text': 'C',
                'actions': [
                  {'type': 'set', 'key': 'display', 'value': '0'},
                ],
              },
            ],
          },
        ],
      },
    });

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  testWidgets('a generated calculator computes when its keys are tapped',
      (tester) async {
    await _pump(tester, JsonUiView(spec: _calculator()));

    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'C'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '7'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '+'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '7'));
    await tester.pump();
    // Bound text follows the state it reads, mid-entry.
    expect(find.text('07+7'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '='));
    await tester.pump();
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('an action that computes nonsense reports instead of crashing',
      (tester) async {
    final errors = <ChatGptException>[];
    final spec = UiSpec.fromJson(<String, dynamic>{
      'state': {'display': '5+'},
      'root': {
        'type': 'button',
        'text': 'go',
        'actions': [
          {'type': 'calc', 'key': 'display', 'expr': '{{display}}'},
        ],
      },
    });

    await _pump(tester, JsonUiView(spec: spec, onError: errors.add));
    await tester.tap(find.widgetWithText(FilledButton, 'go'));
    await tester.pump();

    expect(errors, hasLength(1));
    expect(errors.single, isA<ProtocolException>());
    // The state is left exactly as it was: a failed action changes nothing.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a button with no actions is disabled, not a fake button',
      (tester) async {
    final spec = UiSpec.fromJson(<String, dynamic>{
      'root': {'type': 'button', 'text': 'inert'},
    });

    await _pump(tester, JsonUiView(spec: spec));

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('a new spec starts from its own state, not the old screen\'s',
      (tester) async {
    final first = _calculator();
    await _pump(tester, JsonUiView(spec: first));

    await tester.tap(find.widgetWithText(FilledButton, '7'));
    await tester.pump();
    expect(find.text('07'), findsOneWidget);

    // Generating a second interface must not inherit the first one's display.
    await _pump(tester, JsonUiView(spec: _calculator()));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('07'), findsNothing);
  });

  testWidgets('a textField writes what the user types into bound state',
      (tester) async {
    final spec = UiSpec.fromJson(<String, dynamic>{
      'state': {'name': ''},
      'root': {
        'type': 'column',
        'children': [
          {'type': 'textField', 'text': 'Name', 'stateKey': 'name'},
          {'type': 'text', 'text': 'hola {{name}}'},
        ],
      },
    });

    await _pump(tester, JsonUiView(spec: spec));
    await tester.enterText(find.byType(TextField), 'cristian');
    await tester.pump();

    expect(find.text('hola cristian'), findsOneWidget);
  });

  testWidgets(
      'typing survives a rebuild: the cursor stays where the user left it',
      (tester) async {
    final spec = UiSpec.fromJson(<String, dynamic>{
      'state': {'name': '', 'other': ''},
      'root': {
        'type': 'column',
        'children': [
          {'type': 'textField', 'text': 'Name', 'stateKey': 'name'},
          {
            'type': 'button',
            'text': 'touch',
            'actions': [
              {'type': 'append', 'key': 'other', 'value': 'x'},
            ],
          },
        ],
      },
    });

    await _pump(tester, JsonUiView(spec: spec));
    await tester.enterText(find.byType(TextField), 'cris');

    // Any unrelated action rebuilds the tree. A field that rebuilds its own
    // controller loses the caret here, and the next keystroke lands at the
    // start of the line.
    await tester.tap(find.widgetWithText(FilledButton, 'touch'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'cris');
    expect(field.controller!.selection.baseOffset, 4);
  });

  testWidgets('an action that clears bound state also clears the field',
      (tester) async {
    final spec = UiSpec.fromJson(<String, dynamic>{
      'state': {'name': ''},
      'root': {
        'type': 'column',
        'children': [
          {'type': 'textField', 'text': 'Name', 'stateKey': 'name'},
          {
            'type': 'button',
            'text': 'clear',
            'actions': [
              {'type': 'clear', 'key': 'name'},
            ],
          },
        ],
      },
    });

    await _pump(tester, JsonUiView(spec: spec));
    await tester.enterText(find.byType(TextField), 'cristian');
    await tester.tap(find.widgetWithText(FilledButton, 'clear'));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });
}
