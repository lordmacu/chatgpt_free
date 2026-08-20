import 'dart:async';
import 'dart:convert';

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
}
