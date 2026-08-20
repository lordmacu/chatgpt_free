@Tags(['live'])
library;

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/ui_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The whole point of the proof of concept: can a language model, given only
  // the vocabulary documented in kUiSchemaInstructions, describe an interface
  // this renderer accepts AND that actually works?
  test('the model produces a calculator this renderer accepts', () async {
    final client = ChatGptClient();
    final session = client.newSession();

    final reply = await session.sendJson(
      '$kUiSchemaInstructions\n\nCrea una calculadora simple.',
    );

    final spec = UiSpec.fromJson(reply);

    // Structure
    expect(spec.root.type, isIn(UiNode.kSupportedNodeTypes));
    expect(spec.state, isNotEmpty, reason: 'a calculator needs state');

    // It must be able to compute, not just look like a calculator.
    final actions = <UiAction>[];
    void walk(UiNode n) {
      actions.addAll(n.actions);
      n.children.forEach(walk);
    }

    walk(spec.root);
    expect(actions.map((a) => a.type), contains('calc'),
        reason: 'a calculator with no calc action is a picture of one');
    expect(actions.map((a) => a.type), contains('append'),
        reason: 'digits have to reach the display');

    // Every key an action writes must be declared, or the UI binds to nothing.
    for (final action in actions) {
      expect(spec.state.keys, contains(action.key),
          reason: 'action writes undeclared key "${action.key}"');
    }

    client.close();
  }, timeout: const Timeout(Duration(seconds: 120)));
}
