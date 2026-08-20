import 'dart:async';
import 'dart:convert';

import '../errors.dart';

/// One `event:`/`data:` pair from a text/event-stream response.
class SseFrame {
  /// Creates a frame.
  const SseFrame(this.event, this.data);

  /// The `event:` label, or null for a bare `data:` line.
  final String? event;

  /// The raw `data:` payload, trimmed.
  final String data;
}

/// Decodes [bytes] into [SseFrame]s, ending at the `[DONE]` sentinel.
///
/// The backend keeps writing after `[DONE]`; the stream closes there rather
/// than draining the rest (chatgpt_client.py:588-596 does the same, and
/// skipping it costs seconds per turn).
Stream<SseFrame> readSse(Stream<List<int>> bytes) async* {
  String? event;

  // The Utf8Decoder raises a raw FormatException ("Missing extension byte")
  // when the byte stream ends mid multi-byte character — a connection that
  // drops partway through a UTF-8 sequence produces exactly this. Left
  // unwrapped that FormatException escapes the sealed ChatGptException
  // hierarchy this package promises; `await for` (unlike `yield*`) lets a
  // try/catch here observe an error raised by the delegate stream, so this
  // reclassifies it as ProtocolException — malformed SSE, not a network
  // failure — before it can escape (Final review, Blocker 3).
  try {
    await for (final line in bytes
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        event = null;
        continue;
      }
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('data:')) continue;

      final data = line.substring(5).trim();
      if (data == '[DONE]') return;

      yield SseFrame(event, data);
      event = null;
    }
  } on FormatException catch (e) {
    throw ProtocolException('malformed SSE stream: $e');
  }
}
