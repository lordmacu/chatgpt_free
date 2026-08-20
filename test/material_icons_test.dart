import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression: neither pubspec declared `uses-material-design: true`, so
  // Flutter shipped an empty FontManifest.json and no MaterialIcons-Regular.otf.
  // Every Icons.* in this package's widgets rendered as a fallback CJK glyph on
  // device — including MessageComposer's send button. No widget test can see
  // this: the test renderer resolves icons without the bundled font. Assert the
  // build configuration itself instead.
  test('the package declares uses-material-design', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('uses-material-design: true'),
        reason: 'this package ships widgets that use Material icons, so it must '
            'declare the font or every consumer gets broken glyphs');
  });

  test('the example declares uses-material-design', () {
    final pubspec = File('example/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('uses-material-design: true'));
  });
}
