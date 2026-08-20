import 'package:uuid/uuid.dart';

import 'models/options.dart';

const Uuid _uuid = Uuid();

/// Builds the conversation request body.
///
/// The Android DTO has 47 fields; this sends the subset verified to work and
/// omits optional ones instead of sending nulls. There is deliberately no
/// temperature, top_p or max_tokens — the protocol has no such field.
Map<String, dynamic> buildConversationBody({
  required String message,
  required String model,
  required SendOptions options,
  String? conversationId,
  String? parentMessageId,
  List<String> fileTexts = const [],
  String? systemPrompt,
}) {
  final parts = <String>[
    if (systemPrompt != null && systemPrompt.isNotEmpty)
      '[System instructions: $systemPrompt]',
    if (options.jsonMode)
      'You must respond with valid JSON only. No markdown, no explanations — '
          'just the raw JSON object or array.',
    for (var i = 0; i < fileTexts.length; i++)
      '[Attached file ${i + 1}]:\n${fileTexts[i]}',
    message,
  ];

  final body = <String, dynamic>{
    'action': 'next',
    'parent_message_id': parentMessageId ?? _uuid.v4(),
    'messages': [
      {
        'id': _uuid.v4(),
        'author': {'role': 'user'},
        'content': {
          'content_type': 'text',
          'parts': [parts.join('\n\n')],
        },
        'status': 'finished_successfully',
        'recipient': 'all',
        'metadata': {'model_slug': model, 'default_model_slug': model},
      }
    ],
    'model': model,
    'history_and_training_disabled': false,
    'fork_from_shared_post': false,
    'enable_message_followups': true,
    'force_use_sse': true,
    'force_paragen': false,
    'supported_encodings': ['v1'],
    'supports_buffering': true,
    'timezone_offset_min': 0,
    'system_hints': <String>[],
    'is_onboarding_conversation': false,
    'client_prepare_state': 'none',
    'stream': true,
  };

  // Booleans on the wire. The decompiled app models force_use_search as a
  // Kotlin enum, but sending "ForceSearch" is HTTP 422.
  if (options.webSearch != null) body['force_use_search'] = options.webSearch;
  if (options.tools != null) body['force_use_tools'] = options.tools;
  if (options.canvas != null) body['force_use_canvas'] = options.canvas;
  if (options.thinkingEffort != null) {
    body['thinking_effort'] = options.thinkingEffort!.wire;
  }
  if (options.serviceTier != null) {
    body['service_tier'] = options.serviceTier!.wire;
  }
  if (conversationId != null) body['conversation_id'] = conversationId;

  return body;
}
