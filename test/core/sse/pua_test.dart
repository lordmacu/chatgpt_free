import 'package:chatgpt_free/src/core/sse/pua.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cite = '\u{e200}cite\u{e202}turn0search0\u{e201}';

  test('strips a citation marker from display text', () {
    final out = stripPuaMarkers('La capital es Ulaanbaatar. $cite Además...');
    expect(out, 'La capital es Ulaanbaatar.  Además...');
    expect(out.codeUnits.any((c) => c >= 0xE000 && c <= 0xF8FF), isFalse);
  });

  test('strips genui markers too', () {
    final out = stripPuaMarkers('antes\u{e200}genui\u{e202}{"a":1}\u{e201}después');
    expect(out, 'antesdespués');
  });

  test('strips stray PUA characters with no structure', () {
    expect(stripPuaMarkers('a\u{e203}b'), 'ab');
  });

  test('reports markers with kind, ref and offsets', () {
    final markers = findPuaMarkers('hola $cite fin');
    expect(markers.single.kind, 'cite');
    expect(markers.single.ref, 'turn0search0');
    expect(markers.single.start, 5);
    expect(markers.single.end, 5 + cite.length);
  });

  test('leaves text with no markers untouched', () {
    expect(stripPuaMarkers('texto normal'), 'texto normal');
    expect(findPuaMarkers('texto normal'), isEmpty);
  });
}
