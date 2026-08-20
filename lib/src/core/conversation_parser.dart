import 'dart:convert';

import 'errors.dart';
import 'models/models.dart';

/// Parses `GET /backend-anon/conversation/{id}` into a [ConversationDetail].
///
/// The payload is a `mapping` of node id -> node, forming the conversation
/// tree. Walking it from `current_node` back to the root and reversing gives
/// the turns in order — following `parent` links rather than trusting map
/// order, which is not specified.
ConversationDetail parseConversation(String body, {required String id}) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ProtocolException(
        'conversation $id: body is not JSON: ${_snip(body)}');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ProtocolException('conversation $id: expected an object');
  }

  final mapping = decoded['mapping'];
  if (mapping is! Map) {
    throw ProtocolException('conversation $id: no mapping');
  }

  final ordered = <ChatMessage>[];
  var node = decoded['current_node'];
  final seen = <String>{};

  while (node is String && seen.add(node)) {
    final entry = mapping[node];
    if (entry is! Map) break;

    final message = entry['message'];
    if (message is Map) {
      final role = (message['author'] as Map?)?['role'];
      final parts = (message['content'] as Map?)?['parts'];
      final text = (parts is List && parts.isNotEmpty && parts.first is String)
          ? parts.first as String
          : '';
      // System messages are hidden scaffolding, and empty turns are the tree's
      // root nodes — neither belongs in a transcript.
      if ((role == 'user' || role == 'assistant') && text.trim().isNotEmpty) {
        ordered.add(ChatMessage(role: role! as String, text: text));
      }
    }
    node = entry['parent'];
  }

  return ConversationDetail(
    id: id,
    title: decoded['title'] as String?,
    messages: ordered.reversed.toList(growable: false),
  );
}

String _snip(String s) => s.substring(0, s.length.clamp(0, 200));
