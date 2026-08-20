import 'dart:convert';
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

  /// When set for a call index, that call's fixture stream is cut right
  /// after the line containing this marker text, then throws the paired
  /// error from [midStreamFailures]. Models a connection that drops (or a
  /// malformed frame) partway through a turn, after some frames already
  /// arrived — unlike [failures], which fails before any bytes are ever
  /// returned.
  final Map<int, String> midStreamCutAfter = {};

  /// Errors to throw partway through the fixture stream, paired with
  /// [midStreamCutAfter] by call index.
  final Map<int, Object> midStreamFailures = {};

  /// Every body passed to [stream].
  final List<Map<String, dynamic>> sentBodies = [];

  /// Every device id passed to [stream].
  final List<String> sentDeviceIds = [];

  /// True once [close] has been called.
  bool closeCalled = false;

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
    final marker = midStreamCutAfter[index];
    if (marker == null) return File('test/fixtures/$name.sse').openRead();

    final midFailure = midStreamFailures[index];
    if (midFailure == null) {
      throw StateError(
          'FakeTransport: midStreamCutAfter set for call $index without a '
          'paired midStreamFailures entry');
    }
    final bytes = await File('test/fixtures/$name.sse').readAsBytes();
    return _truncatedThenFailing(bytes, marker, midFailure);
  }

  /// Yields [bytes] up through the end of the line containing [marker], then
  /// throws [error] instead of yielding the rest — a stream error, not a
  /// stream that simply ends early.
  Stream<List<int>> _truncatedThenFailing(
      List<int> bytes, String marker, Object error) async* {
    final needle = utf8.encode(marker);
    final markerStart = _indexOfBytes(bytes, needle);
    if (markerStart == -1) {
      throw StateError('FakeTransport: marker "$marker" not found in fixture');
    }
    var cutoff = markerStart + needle.length;
    final newline = bytes.indexOf(0x0a, cutoff); // '\n'
    if (newline != -1) cutoff = newline + 1;

    yield bytes.sublist(0, cutoff);
    throw error;
  }

  int _indexOfBytes(List<int> haystack, List<int> needle) {
    if (needle.isEmpty) return -1;
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
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
  void close() {
    closeCalled = true;
  }
}
