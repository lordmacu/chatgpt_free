/// The instruction that turns a chat turn into an interface generator.
///
/// Prepend it to the user's request in "developer mode". It documents exactly
/// the vocabulary [UiSpec] parses — nothing aspirational — because anything
/// outside it is rejected rather than guessed at, and a model that invents a
/// node type just produces an error the user has to read.
const String kUiSchemaInstructions = '''
You are generating a user interface as JSON. Respond with ONE JSON object and
nothing else: no prose, no markdown fence.

Shape:
{
  "title": "Calculator",
  "state": { "display": "0" },
  "root": { ...node... }
}

Node types, and only these:
- {"type":"column","gap":8,"align":"start|center|end","children":[...]}
- {"type":"row","gap":8,"children":[...]}
- {"type":"grid","columns":4,"gap":8,"children":[...]}   // wraps every N cells
- {"type":"container","gap":16,"children":[oneChild]}    // padding
- {"type":"spacer"}
- {"type":"text","text":"Total: {{display}}","fontSize":32,"bold":true,"align":"end"}
- {"type":"button","text":"7","actions":[...]}
- {"type":"textField","text":"Label","stateKey":"name"}

Any child may add "flex": 1 to expand inside a row or column.

Text and button labels may contain {{key}} bindings, replaced from state.

Button actions, and only these:
- {"type":"set","key":"display","value":"0"}
- {"type":"append","key":"display","value":"7"}
- {"type":"clear","key":"display"}
- {"type":"backspace","key":"display"}
- {"type":"calc","key":"display","expr":"{{display}}"}

"calc" evaluates arithmetic: + - * / parentheses decimals unary minus. Nothing
else — no functions, no variables beyond {{bindings}}, no comparisons.

Rules:
1. Declare in "state" every key you bind to or write.
2. A button that should do something must have "actions"; one with none renders
   disabled.
3. Keep it to one screen. There is no navigation, no scrolling container, no
   images, no conditionals and no loops.
4. Use the operator characters + - * / in values you append, so "calc" can read
   them back.
''';
