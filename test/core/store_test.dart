import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InMemoryStore round-trips and deletes', () async {
    final store = InMemoryStore();

    expect(await store.read('device_id'), isNull);

    await store.write('device_id', 'abc');
    expect(await store.read('device_id'), 'abc');

    await store.delete('device_id');
    expect(await store.read('device_id'), isNull);
  });
}
