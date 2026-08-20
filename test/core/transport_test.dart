import 'dart:async';
import 'dart:convert';

import 'package:chatgpt_free/src/core/constants.dart';
import 'package:chatgpt_free/src/core/errors.dart';
import 'package:chatgpt_free/src/core/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A fake `http.Client` whose streamed body delivers [chunks] and then
/// fails with [error] instead of ever completing — models a connection
/// dropping partway through the response body, after some bytes already
/// arrived.
class _BodyDropClient extends http.BaseClient {
  _BodyDropClient(this.chunks, this.error);

  final List<List<int>> chunks;
  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    for (final chunk in chunks) {
      controller.add(chunk);
    }
    scheduleMicrotask(() => controller.addError(error));
    return http.StreamedResponse(controller.stream, 200);
  }
}

void main() {
  test('android headers identify the app and the device', () {
    final h = androidHeaders('device-123');

    expect(h['OAI-Device-Id'], 'device-123');
    expect(h['OAI-Client-Type'], 'android');
    expect(h['OAI-Package-Name'], 'com.openai.chatgpt');
    expect(h['User-Agent'], contains(kAppVersion));
    expect(h['X-Device-Tier'], 'lower_mid');
  });

  test('headers carry no Authorization — this client is anonymous only', () {
    expect(androidHeaders('d').containsKey('Authorization'), isFalse);
  });

  test(
      'a connection dropping mid-body surfaces as TransportException, not '
      'the raw http error (Final review, Blocker 3)', () async {
    // stream() already wraps the request phase (_client.send) and the
    // status-line phase; the body itself — response.stream, returned
    // unwrapped — had no equivalent coverage. A real dropped connection
    // raises http.ClientException; any Object works here since the fix
    // wraps whatever the body stream throws.
    final client = _BodyDropClient(
      [utf8.encode('data: {"v":"a"}\n\n')],
      http.ClientException('Connection closed while receiving data'),
    );
    final transport = HttpTransport(client: client);

    final bytes = await transport.stream('/x', {}, deviceId: 'd');

    await expectLater(
      bytes.toList(),
      throwsA(isA<TransportException>()),
    );
  });
}
