import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exceptions are exhaustively switchable', () {
    final errors = <ChatGptException>[
      const QuotaExceededException('spent'),
      const RateLimitedException('slow down', retryAfter: Duration(hours: 1)),
      const InvalidRequestException('bad', field: 'thinking_effort'),
      const TransportException('offline'),
      const ProtocolException('garbled'),
    ];

    final labels = errors.map((e) => switch (e) {
          QuotaExceededException() => 'quota',
          RateLimitedException() => 'rate',
          InvalidRequestException() => 'invalid',
          TransportException() => 'transport',
          ProtocolException() => 'protocol',
        });

    expect(labels, ['quota', 'rate', 'invalid', 'transport', 'protocol']);
  });

  test('InvalidRequestException names the offending field', () {
    const e = InvalidRequestException('bad', field: 'service_tier');
    expect(e.field, 'service_tier');
    expect(e.toString(), contains('service_tier'));
  });
}
