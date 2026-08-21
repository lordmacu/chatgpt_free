import 'dart:convert';

/// Reads JSON, falling back to the Python-literal dialect weaker models emit.
///
/// `repr` output turns up about as often as JSON from a prompted model: single
/// quotes, trailing commas, `True`/`False`/`None`. Python has
/// `ast.literal_eval` for exactly this; Dart does not, so the fallback is a
/// string-aware normalising pass followed by an ordinary decode.
///
/// It is a *rewrite*, never an evaluation: the output is fed to [jsonDecode]
/// like any other text, so there is no execution surface here — nothing in the
/// input can name or call anything.
///
/// Returns null when neither reading works. Never throws.
Object? loadsTolerant(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    // Fall through to the tolerant pass.
  }
  try {
    return jsonDecode(_normalise(text));
  } on FormatException {
    return null;
  }
}

/// Rewrites the Python-literal dialect into JSON.
///
/// String-aware throughout: a `True` inside a quoted value is data and stays
/// exactly as written, and so does a comma or a brace. Only the structure
/// outside strings is touched.
String _normalise(String source) {
  final out = StringBuffer();
  var i = 0;

  while (i < source.length) {
    final ch = source[i];

    if (ch == '"' || ch == "'") {
      final end = _copyString(source, i, out);
      if (end < 0) {
        // An unterminated string: emit the rest verbatim and let the decode
        // reject it. Guessing where it should close would invent content.
        out.write(source.substring(i));
        return out.toString();
      }
      i = end;
      continue;
    }

    if (ch == ',') {
      // A trailing comma is one with nothing but whitespace before the close.
      final next = _nextNonSpace(source, i + 1);
      if (next < source.length &&
          (source[next] == '}' || source[next] == ']')) {
        i++;
        continue;
      }
      out.write(ch);
      i++;
      continue;
    }

    final word = _keywordAt(source, i);
    if (word != null) {
      out.write(word.value);
      i += word.length;
      continue;
    }

    out.write(ch);
    i++;
  }
  return out.toString();
}

/// Copies the string starting at [start] into [out] as a JSON double-quoted
/// string. Returns the index just past it, or -1 if it never closes.
int _copyString(String source, int start, StringBuffer out) {
  final quote = source[start];
  final content = StringBuffer();
  var i = start + 1;

  while (i < source.length) {
    final ch = source[i];
    if (ch == r'\') {
      if (i + 1 >= source.length) return -1;
      final escaped = source[i + 1];
      // A single-quoted string may escape its own quote (\'), which is not a
      // valid JSON escape — unwrap it. Everything else travels as written.
      if (escaped == "'") {
        content.write("'");
      } else {
        content
          ..write(ch)
          ..write(escaped);
      }
      i += 2;
      continue;
    }
    if (ch == quote) {
      out.write(jsonEncode(_decodeEscapes(content.toString())));
      return i + 1;
    }
    content.write(ch);
    i++;
  }
  return -1;
}

/// Turns the JSON escapes still embedded in a copied string back into their
/// characters, so [jsonEncode] can re-escape them exactly once.
String _decodeEscapes(String raw) {
  if (!raw.contains(r'\')) return raw;
  try {
    return jsonDecode('"$raw"') as String;
  } on FormatException {
    return raw;
  }
}

int _nextNonSpace(String source, int from) {
  var i = from;
  while (i < source.length && source[i].trim().isEmpty) {
    i++;
  }
  return i;
}

class _Keyword {
  const _Keyword(this.length, this.value);
  final int length;
  final String value;
}

const Map<String, String> _pythonLiterals = {
  'True': 'true',
  'False': 'false',
  'None': 'null',
};

/// The Python literal starting exactly at [i], if any.
///
/// Bounded by word edges so `NoneOfTheAbove` — an identifier, or a bareword a
/// model wrote — is not rewritten into `nullOfTheAbove`.
_Keyword? _keywordAt(String source, int i) {
  for (final entry in _pythonLiterals.entries) {
    final word = entry.key;
    if (!source.startsWith(word, i)) continue;
    if (i > 0 && _isWordChar(source[i - 1])) continue;
    final after = i + word.length;
    if (after < source.length && _isWordChar(source[after])) continue;
    return _Keyword(word.length, entry.value);
  }
  return null;
}

bool _isWordChar(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
