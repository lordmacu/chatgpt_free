import 'package:chatgpt_free/chatgpt_free.dart';
import 'package:chatgpt_free/ui_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateExpression', () {
    test('respects precedence and parentheses', () {
      expect(evaluateExpression('12+7*2'), 26);
      expect(evaluateExpression('(12+7)*2'), 38);
    });

    test('handles decimals and unary minus', () {
      expect(evaluateExpression('-3.5+1'), closeTo(-2.5, 1e-9));
      expect(evaluateExpression('2*-3'), -6);
    });

    test('reports division by zero rather than returning infinity', () {
      expect(
          () => evaluateExpression('1/0'), throwsA(isA<ProtocolException>()));
    });

    test('rejects anything outside the arithmetic language', () {
      // The point of the limit: a generated document cannot run code.
      for (final bad in ['sqrt(4)', '1+', '', 'a+1', '(1+2']) {
        expect(() => evaluateExpression(bad), throwsA(isA<ProtocolException>()),
            reason: 'should reject "$bad"');
      }
    });
  });

  group('formatNumber', () {
    test('shows whole results without a decimal tail', () {
      expect(formatNumber(4), '4');
      expect(formatNumber(-12), '-12');
    });

    test('keeps real decimals', () {
      expect(formatNumber(2.5), '2.5');
    });
  });
}
