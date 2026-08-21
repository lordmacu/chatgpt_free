import 'dart:convert';
import 'dart:io';

import 'package:chatgpt_free/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart detector must agree with the Python port, case for case.
///
/// The two implementations are ports of each other, and a port drifts
/// silently: each side keeps passing its own tests while quietly answering
/// differently. `test/fixtures/detector_conformance.json` is the shared truth
/// — the same file lives in the chatgpt-proxy repo and pins its detector too —
/// so either side drifting fails here without the other language installed.
void main() {
  final spec = jsonDecode(
          File('test/fixtures/detector_conformance.json').readAsStringSync())
      as Map<String, dynamic>;
  final functions = [
    for (final f in spec['functions'] as List)
      FunctionTool.fromJson(Map<String, dynamic>.from(f as Map)),
  ];
  final names = {for (final n in spec['names'] as List) '$n'};
  final cases = spec['cases'] as List;

  for (var i = 0; i < cases.length; i++) {
    final entry = cases[i] as Map<String, dynamic>;
    test('case $i matches the shared expectation', () {
      final calls =
          detectToolCalls('${entry['input']}', names, functions: functions);
      final actual = calls == null
          ? null
          : [
              for (final c in calls) {'name': c.name, 'arguments': c.arguments},
            ];
      expect(actual, entry['expected'], reason: '${entry['input']}');
    });
  }

  test('the corpus actually exercises detection', () {
    // A corpus that detected nothing would pass vacuously forever.
    final detected = cases.where((c) => (c as Map)['expected'] != null).length;
    expect(detected, greaterThanOrEqualTo(30),
        reason: 'only $detected of ${cases.length} produce calls');
  });
}
