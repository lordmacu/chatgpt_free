import '../core/errors.dart';

/// Evaluates the small arithmetic language the `calc` action uses.
///
/// Supports `+ - * /`, parentheses, decimals and unary minus. Nothing else:
/// this exists so a generated calculator can compute `12+7*2`, not so a model
/// can run code. Anything it does not understand is a [ProtocolException],
/// never a silent wrong number.
double evaluateExpression(String input) {
  final tokens = _tokenise(input);
  final parser = _Parser(tokens, input);
  final value = parser.parseExpression();
  parser.expectEnd();
  return value;
}

sealed class _Token {
  const _Token();
}

final class _Num extends _Token {
  const _Num(this.value);
  final double value;
}

final class _Op extends _Token {
  const _Op(this.symbol);
  final String symbol;
}

List<_Token> _tokenise(String input) {
  final tokens = <_Token>[];
  var i = 0;

  while (i < input.length) {
    final c = input[i];

    if (c.trim().isEmpty) {
      i++;
      continue;
    }

    if (_isDigit(c) || c == '.') {
      final start = i;
      while (i < input.length && (_isDigit(input[i]) || input[i] == '.')) {
        i++;
      }
      final text = input.substring(start, i);
      final value = double.tryParse(text);
      if (value == null) {
        throw ProtocolException('not a number in expression: "$text"');
      }
      tokens.add(_Num(value));
      continue;
    }

    if ('+-*/()'.contains(c)) {
      tokens.add(_Op(c));
      i++;
      continue;
    }

    throw ProtocolException('unexpected "$c" in expression: "$input"');
  }

  if (tokens.isEmpty) throw ProtocolException('empty expression: "$input"');
  return tokens;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

/// Recursive descent: expression → term → factor. Small enough to read, which
/// matters more here than speed.
class _Parser {
  _Parser(this._tokens, this._source);

  final List<_Token> _tokens;
  final String _source;
  int _at = 0;

  _Token? get _current => _at < _tokens.length ? _tokens[_at] : null;

  bool _eatOp(String symbol) {
    final token = _current;
    if (token is _Op && token.symbol == symbol) {
      _at++;
      return true;
    }
    return false;
  }

  double parseExpression() {
    var value = _parseTerm();
    while (true) {
      if (_eatOp('+')) {
        value += _parseTerm();
      } else if (_eatOp('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      if (_eatOp('*')) {
        value *= _parseFactor();
      } else if (_eatOp('/')) {
        final divisor = _parseFactor();
        // Division by zero is a real outcome of a calculator, not a crash:
        // report it as a protocol error so the UI can show it.
        if (divisor == 0) {
          throw const ProtocolException('division by zero');
        }
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    if (_eatOp('-')) return -_parseFactor();
    if (_eatOp('+')) return _parseFactor();

    if (_eatOp('(')) {
      final value = parseExpression();
      if (!_eatOp(')')) {
        throw ProtocolException('unclosed "(" in expression: "$_source"');
      }
      return value;
    }

    final token = _current;
    if (token is _Num) {
      _at++;
      return token.value;
    }

    throw ProtocolException('incomplete expression: "$_source"');
  }

  void expectEnd() {
    if (_at != _tokens.length) {
      throw ProtocolException('trailing input in expression: "$_source"');
    }
  }
}

/// Formats a computed value the way a calculator display would: `4`, not `4.0`.
String formatNumber(double value) {
  if (value.isNaN || value.isInfinite) return 'Error';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value
      .toStringAsFixed(10)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}
