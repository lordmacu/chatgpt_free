import 'dart:async';

import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A client whose response never arrives, and one whose body stalls mid-stream.
class _HangingClient extends http.BaseClient {
  _HangingClient({required this.headersArrive});

  final bool headersArrive;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!headersArrive) return Completer<http.StreamedResponse>().future;
    // Headers arrive, then the body never emits and never closes.
    final controller = StreamController<List<int>>();
    return Future.value(http.StreamedResponse(controller.stream, 200));
  }
}

void main() {
  // Regression, found by installing the demo on a phone: a turn that stalled
  // showed a spinner forever with no error, because the transport had no
  // timeout at all while the Python client it is ported from uses 60s read /
  // 10s connect.
  test('a request with no response headers fails as TransportException',
      () async {
    final transport = HttpTransport(
      client: _HangingClient(headersArrive: false),
      connectTimeout: const Duration(milliseconds: 120),
    );

    await expectLater(
      transport.stream('/backend-anon/f/conversation', const {},
          deviceId: 'd'),
      throwsA(isA<TransportException>()
          .having((e) => e.message, 'message', contains('response headers'))),
    );
  });

  test('a body that stalls mid-stream fails as TransportException', () async {
    final transport = HttpTransport(
      client: _HangingClient(headersArrive: true),
      idleTimeout: const Duration(milliseconds: 120),
    );

    final body = await transport
        .stream('/backend-anon/f/conversation', const {}, deviceId: 'd');

    await expectLater(
      body.drain<void>(),
      throwsA(isA<TransportException>()
          .having((e) => e.message, 'message', contains('stalled'))),
    );
  });
}
