/// Where the package keeps the little state that should survive a restart:
/// the device id and the current conversation id.
///
/// The package ships no platform storage on purpose. Depending on
/// shared_preferences would force that choice on every consumer; implement
/// this against whatever your app already uses.
abstract interface class ChatGptStore {
  /// Reads a value, or null when absent.
  Future<String?> read(String key);

  /// Writes a value.
  Future<void> write(String key, String value);

  /// Deletes a value.
  Future<void> delete(String key);
}

/// The default store. State lives as long as the process does.
class InMemoryStore implements ChatGptStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
