import '../core/client.dart';
import '../core/errors.dart';
import '../core/events.dart';
import '../core/models/options.dart';
import 'envelope.dart';
import 'function_tool.dart';
import 'prompt.dart';
import 'schema_check.dart';

/// What one extraction produced.
sealed class ToolExtraction {
  /// Creates a result.
  const ToolExtraction({
    required this.requests,
    this.notes = const [],
    this.raw = '',
  });

  /// Upstream messages this cost. One on the happy path; two when a repair or
  /// an audit ran. They come out of the same anonymous hourly allowance as
  /// ordinary chat.
  final int requests;

  /// What had to be tolerated, for logging — `fenced`, `repaired`, `verified`.
  final List<String> notes;

  /// The model's last raw reply, for when something needs eyeballing.
  final String raw;
}

/// The model chose one or more functions.
final class ToolCallsExtracted extends ToolExtraction {
  /// Creates it.
  const ToolCallsExtracted(
    this.calls, {
    required super.requests,
    super.notes,
    super.raw,
  });

  /// The calls to execute, in order.
  final List<ToolCall> calls;
}

/// No declared function fits — answer the user the ordinary way.
final class NoToolCall extends ToolExtraction {
  /// Creates it.
  const NoToolCall({
    required super.requests,
    this.errors = const [],
    super.notes,
    super.raw,
  });

  /// Why, when the reason was a rejection rather than a plain "none fits".
  /// Empty means the model simply said no function applied.
  final List<String> errors;
}

/// A required parameter was never stated in the request.
///
/// Emitted instead of a guess. Without this option the model invented an
/// origin airport and a date the user never gave, and the invention validated
/// cleanly against the schema — a wrong call that looks exactly like a right
/// one is the worst outcome available here.
final class ToolInfoNeeded extends ToolExtraction {
  /// Creates it.
  const ToolInfoNeeded({
    required this.function,
    required this.missing,
    required super.requests,
    super.notes,
    super.raw,
  });

  /// The function the model would have called.
  final String function;

  /// The parameters it could not fill from the request.
  final List<String> missing;
}

/// Custom function calling, emulated on a backend that has none.
///
/// The conversation protocol has nowhere to *declare* a caller's functions:
/// the only tool flags it understands switch on tools that run inside OpenAI
/// and come back as prose. So calls are produced the way JSON mode already is
/// — by prompt — but through a dedicated, stateless request rather than the
/// conversation itself.
///
/// That separation is the whole design, not an implementation detail.
/// Measured anonymously on 2026-08-20: with the manifest in a live
/// conversation's system prompt, "weather in Lima and Quito" produced a usable
/// envelope **0 times out of 5** — the model answered from its own web search
/// instead, and turning search off did not reliably stop it. With the manifest
/// in the user turn of a throwaway session, the same request went **4 for 4**,
/// and 25 of 28 over a wider battery, with no false positives on 8 prompts
/// that needed no function at all.
///
/// So: an extraction is not part of a conversation and cannot see one. Feed it
/// the user's request, run whatever calls come back yourself, and send the
/// results into your chat session as ordinary text.
///
/// ```dart
/// final extractor = ToolExtractor(client: client);
/// final result = await extractor.extract(
///   'weather in Lima and Quito',
///   functions: [
///     const FunctionTool(
///       name: 'get_weather',
///       description: 'Current weather for a city',
///       parameters: {
///         'type': 'object',
///         'properties': {'city': {'type': 'string'}},
///         'required': ['city'],
///       },
///     ),
///   ],
/// );
///
/// switch (result) {
///   case ToolCallsExtracted(:final calls):
///     for (final call in calls) await run(call.name, call.arguments);
///   case ToolInfoNeeded(:final missing):
///     ask(user, 'I still need: ${missing.join(', ')}');
///   case NoToolCall():
///     await session.send(request);
/// }
/// ```
class ToolExtractor {
  /// Creates an extractor over [client].
  ///
  /// [model] is passed through for completeness, but the anonymous backend
  /// picks its own model and ignores the request — do not expect a change here
  /// to alter the outcome. It matters only if this package is ever pointed at
  /// a backend that honours it.
  ToolExtractor({required this.client, this.model = 'auto'});

  /// The client whose transport and quota the extraction spends.
  final ChatGptClient client;

  /// The model asked for. See the constructor's note.
  final String model;

  /// Turns [request] into calls against [functions].
  ///
  /// Costs one upstream message, two if the first reply had to be repaired
  /// (measured at about 1 in 30) or if [verify] is on.
  ///
  /// [verify] spends a second message re-reading the original request for a
  /// condition the first pass dropped. That is the one real failure mode: a
  /// request packing about six conditions loses one, and the result still
  /// validates, so no amount of schema checking finds it. The audit recovered
  /// the lost filter in measurement (2/4 to 3/4). Worth it for dense
  /// multi-condition requests, wasteful for "the weather in Bogotá".
  Future<ToolExtraction> extract(
    String request, {
    required List<FunctionTool> functions,
    ToolChoice choice = ToolChoice.auto,
    bool verify = false,
  }) async {
    if (functions.isEmpty) {
      throw ArgumentError.value(
          functions, 'functions', 'declare at least one function');
    }

    final prompt = buildExtractorPrompt(functions, request, choice: choice);
    var raw = await _ask(prompt);
    final envelope = parseToolEnvelope(raw);
    var spent = 1;
    var notes = [...envelope.notes];

    if (envelope is EnvelopeNeedInfo) {
      return ToolInfoNeeded(
        function: envelope.function,
        missing: envelope.missing,
        requests: spent,
        notes: notes,
        raw: raw,
      );
    }

    var calls = envelope is EnvelopeCalls ? toToolCalls(envelope.calls) : null;
    var errors =
        calls == null ? const <String>[] : validateToolCalls(calls, functions);

    // Repair runs only when the first pass produced something unusable, which
    // measured at 1 in 30 — a safety net, not a second leg of the flow.
    if (calls == null || errors.isNotEmpty) {
      spent++;
      final repaired = await _ask(buildRepairPrompt(prompt, raw, errors));
      final second = parseToolEnvelope(repaired);

      if (second is EnvelopeNeedInfo) {
        return ToolInfoNeeded(
          function: second.function,
          missing: second.missing,
          requests: spent,
          notes: [...notes, 'repaired'],
          raw: repaired,
        );
      }

      final secondCalls =
          second is EnvelopeCalls ? toToolCalls(second.calls) : null;
      final secondErrors = secondCalls == null
          ? const <String>[]
          : validateToolCalls(secondCalls, functions);

      if (secondCalls != null && secondErrors.isEmpty) {
        calls = secondCalls;
        errors = const [];
        raw = repaired;
        notes = [...notes, 'repaired'];
      } else {
        calls = secondCalls ?? calls;
        errors = secondErrors.isNotEmpty ? secondErrors : errors;
        notes = [...notes, ...second.notes, 'repair-failed'];
      }
    }

    if (calls == null) {
      return NoToolCall(
          requests: spent, errors: errors, notes: notes, raw: raw);
    }

    if (calls.isNotEmpty && verify) {
      spent++;
      final audited = await _ask(buildVerifyPrompt(functions, request, calls));
      final third = parseToolEnvelope(audited);
      if (third is EnvelopeCalls) {
        final auditedCalls = toToolCalls(third.calls);
        // Only accept the audit when it is at least as valid as what it
        // replaces — an auditor that returns junk must not destroy a good
        // first pass.
        if (auditedCalls.isNotEmpty &&
            validateToolCalls(auditedCalls, functions).isEmpty) {
          calls = auditedCalls;
          raw = audited;
          notes = [...notes, 'verified'];
        }
      }
    }

    if (calls.isEmpty) {
      return NoToolCall(
          requests: spent, errors: errors, notes: notes, raw: raw);
    }
    return ToolCallsExtracted(calls, requests: spent, notes: notes, raw: raw);
  }

  /// One throwaway session, one message, no history.
  ///
  /// A fresh session per ask is the point: an extraction has no conversation,
  /// and the measurement above says it must not appear to have one. The
  /// session gets its own [InMemoryStore] rather than the client's, so a
  /// throwaway device id never overwrites the app's persisted one.
  Future<String> _ask(String prompt) async {
    final session = client.newEphemeralSession();
    final buffer = StringBuffer();
    try {
      await for (final event in client.sendWithRotation(
        session,
        prompt,
        // The server-side tools are the competition, not the helpers: with
        // search on, the model answers the question itself instead of
        // delegating to the caller's function.
        options: SendOptions(model: model, webSearch: false, tools: false),
      )) {
        if (event is TextDelta) buffer.write(event.text);
      }
    } on ChatGptException {
      session.close();
      rethrow;
    }
    session.close();
    return buffer.toString().trim();
  }
}
