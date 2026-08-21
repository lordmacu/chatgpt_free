import 'dart:convert';

import 'function_tool.dart';

/// The marker a call is wrapped in.
///
/// A marker rather than "reply in JSON" for two reasons: an ordinary answer
/// that happens to contain a JSON block is not mistaken for a call, and the
/// marker lands in the first streamed chunk, so a caller can tell a call from
/// prose after a handful of characters.
const String kToolCallMarker = '<<<TOOL_CALL>>>';

/// The marker for "no declared function fits this request".
const String kNoToolMarker = '<<<NO_TOOL>>>';

/// The marker for "a required parameter was never stated".
const String kNeedInfoMarker = '<<<NEED_INFO>>>';

/// Builds the extractor prompt.
///
/// Every rule below was earned by a failing measurement, not written from
/// taste. The two that carry the most weight:
///
/// * The manifest goes in the *user* turn of a throwaway session, never in a
///   live conversation's system prompt. Measured on the same request, the
///   latter produced a usable envelope 0 times out of 5 — the model answered
///   from its own web search instead — while the former went 4 for 4, and 25
///   of 28 over a wider battery.
/// * "You have NO knowledge about anything a function covers." Without it the
///   model answers the request itself whenever it believes it knows how,
///   weather being the worst offender.
String buildExtractorPrompt(
  List<FunctionTool> functions,
  String request, {
  ToolChoice choice = ToolChoice.auto,
}) {
  final forcedName = choice is NamedToolChoice ? choice.name : null;
  final mustCall = choice is! AutoToolChoice;

  final options = <String>[
    '  A) $kToolCallMarker{"calls":[{"name":"<function name>","arguments":{...}}]}',
    if (!mustCall)
      '  B) $kNoToolMarker   (no declared function fits the request)',
    '  C) $kNeedInfoMarker{"function":"<name>","missing":["<param>"]}   '
        '(a REQUIRED parameter is not stated in the request)',
  ];

  return [
    'You are a function-call extractor. You do not chat and you do not answer '
        'questions.',
    '',
    'AVAILABLE FUNCTIONS (JSON Schema):',
    jsonEncode([for (final f in functions) f.toJson()]),
    '',
    if (mustCall)
      'You MUST call a function. Output ONLY one of these:'
    else
      'Read the USER REQUEST below and output ONLY one of these:',
    ...options,
    '',
    'RULES:',
    '- Nothing before or after the output. No prose, no markdown fences, no '
        'explanation.',
    '- Output the marker exactly once.',
    '- You have NO knowledge and NO live data about anything a function covers. '
        'If a',
    '  function covers the request you MUST emit the call, even if you think '
        'you know',
    '  the answer. Answering it yourself is an ERROR.',
    '- "arguments" must satisfy that function\'s JSON Schema exactly. Never '
        'invent parameters.',
    '- One entry per distinct set of arguments: two cities means two calls.',
    '- Only omit an OPTIONAL parameter when the request does not specify it.',
    '- NEVER guess, infer or default a REQUIRED parameter the request does not '
        'state',
    '  (no made-up cities, dates, ids or amounts). If one is missing, output '
        'option C.',
    '- Never invent or simulate the RESULT of a function.',
    '- Capture EVERY condition stated in the request. Dropping one is an error.',
    if (forcedName != null)
      '- You MUST call the function "$forcedName" and no other.'
    else if (mustCall)
      '- Emitting $kNoToolMarker is forbidden for this request.',
    '',
    '---',
    'USER REQUEST:',
    request,
  ].join('\n');
}

/// Builds the audit prompt for the opt-in second pass.
///
/// The one failure mode the first pass really has is a dropped condition: a
/// request packing about six of them loses one, and the result still validates
/// against the schema, so no amount of checking finds it. Re-reading the
/// original request is the only thing that does.
String buildVerifyPrompt(
  List<FunctionTool> functions,
  String request,
  List<ToolCall> calls,
) =>
    'You are a completeness auditor for an extracted function call.\n\n'
    'ORIGINAL REQUEST:\n$request\n\n'
    'EXTRACTED CALL:\n'
    '${jsonEncode([
          for (final c in calls) {'name': c.name, 'arguments': c.arguments}
        ])}\n\n'
    'FUNCTION SCHEMAS:\n'
    '${jsonEncode([for (final f in functions) f.toJson()])}\n\n'
    'Find every condition stated in the ORIGINAL REQUEST that is NOT '
    'represented in the\n'
    'EXTRACTED CALL, then output the corrected call. If nothing is missing, '
    'output the\n'
    'extracted call unchanged.\n'
    'Output ONLY:\n'
    '$kToolCallMarker{"calls":[{"name":"...","arguments":{...}}]}';

/// Builds the repair prompt: the original ask plus what was wrong with the
/// answer to it.
String buildRepairPrompt(
        String original, String previous, List<String> errors) =>
    '$original\n\n---\nYour previous output was rejected:\n'
    '${previous.length > 600 ? previous.substring(0, 600) : previous}\n'
    'Errors: ${errors.isEmpty ? 'output did not match the required format' : errors.join('; ')}\n'
    'Output the corrected marker line and nothing else.';
