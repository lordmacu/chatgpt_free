import 'dart:convert';

import 'package:chatgpt_free/src/core/errors.dart';
import 'package:chatgpt_free/src/core/sse/reader.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> _bytes(String s) => Stream.value(utf8.encode(s));

void main() {
  test('pairs event lines with their data line', () async {
    const raw = 'event: delta_encoding\n'
        'data: "v1"\n'
        '\n'
        'event: delta\n'
        'data: {"o":"append","v":"hola"}\n'
        '\n';

    final frames = await readSse(_bytes(raw)).toList();

    expect(frames.length, 2);
    expect(frames[0].event, 'delta_encoding');
    expect(frames[0].data, '"v1"');
    expect(frames[1].event, 'delta');
    expect(frames[1].data, '{"o":"append","v":"hola"}');
  });

  test('emits data-only frames with a null event', () async {
    const raw = 'data: {"type":"message_stream_complete"}\n\n';

    final frames = await readSse(_bytes(raw)).toList();

    expect(frames.single.event, isNull);
    expect(frames.single.data, '{"type":"message_stream_complete"}');
  });

  test('stops at [DONE] and drops everything after it', () async {
    const raw = 'data: {"v":"a"}\n'
        '\n'
        'data: [DONE]\n'
        '\n'
        'data: {"v":"ignored"}\n'
        '\n';

    final frames = await readSse(_bytes(raw)).toList();

    expect(frames.length, 1);
    expect(frames.single.data, '{"v":"a"}');
  });

  test(
      'a truncated multi-byte UTF-8 sequence raises ProtocolException, not '
      'a raw FormatException (Final review, Blocker 3)', () async {
    // 0xC3 is the lead byte of a 2-byte UTF-8 sequence (e.g. 'é' is 0xC3
    // 0xA9); ending the stream right after it — with no continuation byte
    // ever coming — is exactly what a connection dropping mid-character
    // produces. The Utf8Decoder used inside readSse raises a raw
    // FormatException("Missing extension byte") for this; that must not
    // escape the sealed ChatGptException hierarchy.
    final chunks = Stream<List<int>>.fromIterable([
      [...utf8.encode('data: caf'), 0xC3],
    ]);

    await expectLater(
      readSse(chunks).toList(),
      throwsA(isA<ProtocolException>()),
    );
  });

  test('handles a payload split across chunk boundaries', () async {
    final chunks = Stream.fromIterable([
      utf8.encode('event: del'),
      utf8.encode('ta\ndata: {"v":"par'),
      utf8.encode('tido"}\n\n'),
    ]);

    final frames = await readSse(chunks).toList();

    expect(frames.single.event, 'delta');
    expect(frames.single.data, '{"v":"partido"}');
  });
}
