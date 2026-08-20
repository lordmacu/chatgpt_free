import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression, seen on device: switching tabs triggered loadHistory(), which
  // replaced the clean local text with the server's copy — and the server's
  // copy of a user turn contains everything this package prepends to it.
  test('strips the system prompt from a fetched user turn', () {
    const wire = '[System instructions: Answer briefly.]\n\nhola';
    expect(stripPromptScaffolding(wire), 'hola');
  });

  test('strips the JSON instruction and its retraction', () {
    const json = 'You must respond with valid JSON only. No markdown, no '
        'explanations — just the raw JSON object or array.\n\ncómo estás';
    expect(stripPromptScaffolding(json), 'cómo estás');

    const back = 'Stop answering in JSON. Reply in ordinary prose from now on, '
        'unless I ask for JSON again.\n\nquién fue Bolívar';
    expect(stripPromptScaffolding(back), 'quién fue Bolívar');
  });

  test('strips several stacked blocks at once', () {
    const wire = '[System instructions: Answer briefly.]\n\n'
        'You must respond with valid JSON only. No markdown.\n\n'
        '[Attached file 1]:\nlorem ipsum\n\n'
        'resume el archivo';
    expect(stripPromptScaffolding(wire), 'resume el archivo');
  });

  test('leaves an ordinary message untouched', () {
    expect(stripPromptScaffolding('hola, cómo estás'), 'hola, cómo estás');
  });

  test('never erases a message that only looks like scaffolding', () {
    // Nothing but scaffolding means we misread it — return the text, not ''.
    const only = '[System instructions: Answer briefly.]';
    expect(stripPromptScaffolding(only), only);
  });

  test('keeps a later block that happens to start like a marker', () {
    const wire = 'hola\n\nYou must respond with valid JSON only.';
    expect(stripPromptScaffolding(wire), wire);
  });
}
