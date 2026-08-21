/// Custom function calling, emulated on a backend that has none.
///
/// Import this only if you want it: it is a separate library from
/// `package:chatgpt_free/chatgpt_free.dart`, so a consumer who just wants the
/// chat client never sees any of it.
///
/// Start at [ToolExtractor].
library;

export 'src/tools/envelope.dart'
    show
        ToolEnvelope,
        EnvelopeCalls,
        EnvelopeNeedInfo,
        EnvelopeUnreadable,
        parseToolEnvelope;
export 'src/tools/detect.dart' show allowedNames, detectToolCalls;
export 'src/tools/extractor.dart';
export 'src/tools/function_tool.dart';
export 'src/tools/prompt.dart';
export 'src/tools/schema_check.dart';
export 'src/tools/schema_coerce.dart' show applySchemas, coerceValue;
export 'src/tools/tolerant_json.dart' show loadsTolerant;
