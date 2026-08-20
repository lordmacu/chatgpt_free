import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'constants.dart';
import 'errors.dart';

const Uuid _uuid = Uuid();

/// Headers every request to the anonymous backend carries.
///
/// Ported from chatgpt_client.py:141-158. Notably there is no Authorization
/// header: identity is the device id and nothing else.
Map<String, String> androidHeaders(String deviceId) => {
      'User-Agent':
          'ChatGPT/$kAppVersion (Android 16; sdk_gphone64_arm64; build 2622307)',
      'OAI-Package-Name': 'com.openai.chatgpt',
      'OAI-Client-Type': 'android',
      'OAI-Device-Id': deviceId,
      'Accept-Language': 'en-US,en;q=0.9',
      'X-Device-Tier': 'lower_mid',
      'ChatGPT-Account-ID': 'default',
      'ChatGPT-Residency-Region': 'no_constraint',
      'Accept': 'application/json',
    };

/// How the package reaches the backend. Swap it out in tests.
abstract interface class Transport {
  /// Opens a streaming POST and yields the raw response bytes.
  Future<Stream<List<int>>> stream(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  });

  /// Performs a GET and returns the body as text.
  Future<String> get(String path, {required String deviceId});

  /// Performs a POST and returns the body as text.
  Future<String> post(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  });

  /// Releases underlying resources.
  void close();
}

/// The real transport, over `package:http`.
class HttpTransport implements Transport {
  /// Creates a transport, optionally over a supplied [client].
  HttpTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _turnHeaders(String deviceId, String path) => {
        ...androidHeaders(deviceId),
        'Accept': 'text/event-stream, application/json',
        'Cache-Control': 'no-cache',
        'X-Sentinel-Payload': kSentinelPayload,
        'oai-session-id': _uuid.v4(),
        'x-oai-convo-session-id': _uuid.v4(),
        'x-oai-turn-trace-id': _uuid.v4(),
        'X-OpenAI-Target-Path': path,
        'Content-Type': 'application/json',
      };

  Never _throwForStatus(int status, String body) {
    if (status == 429 || status == 403) {
      throw RateLimitedException(
          body.isEmpty ? 'HTTP $status' : body.substring(0, body.length.clamp(0, 300)));
    }
    if (status == 422) {
      throw InvalidRequestException(
          body.isEmpty ? 'HTTP 422' : body.substring(0, body.length.clamp(0, 300)));
    }
    throw TransportException('HTTP $status: ${body.substring(0, body.length.clamp(0, 300))}');
  }

  @override
  Future<Stream<List<int>>> stream(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async {
    final request = http.Request('POST', Uri.parse('$kBaseUrl$path'))
      ..headers.addAll(_turnHeaders(deviceId, path))
      ..bodyBytes = utf8.encode(jsonEncode(body));

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on Object catch (e) {
      throw TransportException('$e');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      _throwForStatus(response.statusCode, text);
    }
    return response.stream;
  }

  @override
  Future<String> get(String path, {required String deviceId}) async {
    try {
      final r = await _client.get(
        Uri.parse('$kBaseUrl$path'),
        headers: {...androidHeaders(deviceId), 'X-OpenAI-Target-Path': path},
      );
      if (r.statusCode != 200) _throwForStatus(r.statusCode, r.body);
      return r.body;
    } on ChatGptException {
      rethrow;
    } on Object catch (e) {
      throw TransportException('$e');
    }
  }

  @override
  Future<String> post(
    String path,
    Map<String, dynamic> body, {
    required String deviceId,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$kBaseUrl$path'),
        headers: {
          ...androidHeaders(deviceId),
          'X-OpenAI-Target-Path': path,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (r.statusCode != 200) _throwForStatus(r.statusCode, r.body);
      return r.body;
    } on ChatGptException {
      rethrow;
    } on Object catch (e) {
      throw TransportException('$e');
    }
  }

  @override
  void close() => _client.close();
}
