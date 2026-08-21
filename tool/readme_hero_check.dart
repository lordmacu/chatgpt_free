// The README block uses `print`, because that is what a reader would write.
// This file is a copy of documentation, not production code.
// ignore_for_file: avoid_print

/// The code block at the very top of the README, compiled.
///
/// It is the first thing anyone sees, so it is the worst place for a snippet
/// that does not compile. Nothing here runs — no `main`, and the function is
/// never called, which also keeps `File('report.txt')` from being opened by
/// anyone who tries. `flutter analyze` covers it like any other file.
library;

import 'dart:io';

import 'package:chatgpt_free/chatgpt_free.dart';

// ignore: unused_element
Future<void> _theBlockAtTheTopOfTheReadme() async {
  final client = ChatGptClient();
  final session = client.newSession();

  // Ask, and get the whole answer back.
  print(await session.ask('Explain recursion in one sentence.'));

  // Or watch it being written.
  await for (final event in session.send('Tell me a very short story.')) {
    if (event is TextDelta) stdout.write(event.text);
  }

  // Search the web, and see the sources it used.
  await for (final event in session.send(
    "What are today's top tech headlines?",
    options: const SendOptions(webSearch: true),
  )) {
    if (event is CitationsReceived) {
      for (final c in event.citations) {
        print('${c.title} — ${c.url}');
      }
    }
  }

  // Ask for JSON and get it decoded.
  print(await session.sendJson('Three planets with their diameter.'));

  // Send a file along: its text is inlined into the prompt.
  await session.ask('Summarise this.', attachments: [
    TextAttachment(
        name: 'report.txt', content: File('report.txt').readAsStringSync()),
  ]);

  // Translate — a different endpoint, so it spends no chat message and keeps
  // working after the hourly cap has stopped the chat.
  print(await client.translate('The quick brown fox', target: 'es'));

  // What is left of the anonymous quota, and when it comes back.
  final limits = await session.limits();
  print(
      '${limits.remaining['file_upload']} uploads, back ${limits.resetAfter['file_upload']}');

  client.close();
}
