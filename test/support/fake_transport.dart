import 'dart:io';

import 'package:chatgpt_free/src/core/transport.dart';

/// A transport that replays recorded fixtures and records what it was asked.
class FakeTransport implements Transport {
  FakeTransport({List<String>? fixtures, this.getResponse = '{}'})
      : _fixtures = fixtures ?? ['plain_text'];

  final List<String> _fixtures;
  int _call = 0;

  /// Body returned by [get] and [post].
  String getResponse;

  /// Errors to throw instead of replaying, indexed by call number.
  final Map<int, Object> failures = {};

  /// Every body passed to [stream].
  final List<Map<String, dynamic>> sentBodies = [];

  /// Every device id passed to [stream].
  final List<String> sentDeviceIds = [];

  @override
  Future<Stream<List<int>>> stream(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async {
    final index = _call++;
    sentBodies.add(body);
    sentDeviceIds.add(deviceId);

    final failure = failures[index];
    if (failure != null) throw failure;

    final name = _fixtures[index.clamp(0, _fixtures.length - 1)];
    return File('test/fixtures/$name.sse').openRead();
  }

  @override
  Future<String> get(String path, {required String deviceId}) async =>
      getResponse;

  @override
  Future<String> post(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async =>
      getResponse;

  @override
  void close() {}
}
