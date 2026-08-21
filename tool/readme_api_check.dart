/// Every member the README's "The library in one page" section promises.
///
/// Nothing here runs — there is no `main`, and [_everyDocumentedMember] is
/// never called. It exists to be COMPILED: `flutter analyze` covers this file
/// like any other, so a README that misstates a signature stops the analyzer
/// instead of misleading a reader. It has already caught one: the section
/// claimed `translate(text, targetLanguageCode: …)` when the parameter is
/// `target`.
///
/// Deliberately no `main`: several of these calls would reach the real
/// backend and spend an anonymous message if anyone ran the file.
library;

import 'package:chatgpt_free/tools.dart';
import 'package:chatgpt_free/ui_schema.dart';
import 'package:chatgpt_free/widgets.dart';

// ignore: unused_element
Future<void> _everyDocumentedMember() async {
  final client = ChatGptClient(maxRotations: 1, store: InMemoryStore());

  final ChatGptSession a = client.newSession(systemPrompt: 'x');
  final ChatGptSession b = client.newEphemeralSession();
  final ChatGptSession c = await client.restoreSession();

  final List<ModelInfo> models = await client.models();
  final Limits clientLimits = await client.limits();
  final String es = await client.translate('hi', target: 'es', source: 'en');

  const options = SendOptions(
    model: 'gpt-5-6',
    webSearch: true,
    tools: false,
    canvas: null,
    jsonMode: false,
    thinkingEffort: ThinkingEffort.max,
    serviceTier: ServiceTier.priority,
  );
  final withJson = options.copyWith(jsonMode: true);

  var buffer = '';
  await for (final event in client.sendWithRotation(a, 'hola',
      options: withJson,
      attachments: [const TextAttachment(name: 'n.txt', content: 'x')])) {
    switch (event) {
      case TextDelta(:final text, :final isReset):
        buffer = isReset ? text : buffer + text;
      case SearchStarted(:final queries):
        queries.length;
      case CitationsReceived(:final citations):
        citations.length;
      case CanvasDocument(:final markdown, :final title):
        '$markdown$title';
      case GenuiWidgetEvent(:final name, :final data):
        '$name${data.length}';
      case ImageGenerated(:final url):
        url.length;
      case ModelDowngraded(:final requested, :final actual):
        '$requested$actual';
      case ConversationTitled(:final title):
        title.length;
      case QuotaRotated(:final reason):
        reason.length;
      case ReplyCompleted():
        break;
      case TurnCompleted(
          :final actualModel,
          :final finishReason,
          :final limits
        ):
        '$actualModel$finishReason${limits?.remaining}${limits?.resetAfter}';
    }
  }

  final Object? json = await a.sendJson('dame json');
  final ConversationDetail? detail = await a.loadHistory();
  final Limits own = await a.limits();
  a.rotateDevice();
  await a.reset();
  final String device = a.deviceId;
  final String? conv = a.conversationId;
  final String? title = a.title;
  final List<ChatMessage> history = a.history;
  a.close();

  try {
    await b.send('x').drain<void>();
  } on ChatGptException catch (e) {
    switch (e) {
      case RateLimitedException():
      case QuotaExceededException():
      case InvalidRequestException():
      case TransportException():
      case ProtocolException():
        e.message.length;
    }
  }

  // Las dos librerías opcionales.
  final extraction = await ToolExtractor(client: client).extract(
    'weather in Lima',
    functions: const [FunctionTool(name: 'get_weather')],
    choice: ToolChoice.auto,
    verify: false,
  );
  switch (extraction) {
    case ToolCallsExtracted(:final calls):
      calls.first.name;
    case ToolInfoNeeded(:final missing):
      missing.length;
    case NoToolCall():
      break;
  }
  UiSpec.fromJson(<String, dynamic>{
    'root': {'type': 'text', 'text': 'x'}
  });

  // La capa Flutter.
  final controller = ChatController(client: client);
  controller.currentOptions;
  controller.dispose();

  '$b$c$models$clientLimits$es$buffer$json$detail$own$device$conv$title$history';
}
