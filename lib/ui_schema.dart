/// A tiny JSON vocabulary for describing a Flutter screen, and a renderer for
/// it — a proof of concept for having a language model build an interface.
///
/// Import this only if you want it: it is deliberately a separate library from
/// `package:chatgpt_free/chatgpt_free.dart`, so a consumer who just wants the
/// chat client never sees any of it.
library;

export 'src/uikit/expression.dart' show evaluateExpression, formatNumber;
export 'src/uikit/prompt.dart';
export 'src/uikit/renderer.dart';
export 'src/uikit/schema.dart';
