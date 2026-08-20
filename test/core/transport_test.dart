import 'package:chatgpt_free/src/core/constants.dart';
import 'package:chatgpt_free/src/core/transport.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
