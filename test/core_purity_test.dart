import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing under lib/src/core imports Flutter', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/src/core').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("package:flutter/")) offenders.add(entity.path);
    }

    expect(offenders, isEmpty,
        reason: 'core must stay pure Dart so it is testable and extractable');
  });
}
