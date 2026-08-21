// Runs the shared corpus through the Dart detector and prints one JSON line
// per case, so it can be diffed against the Python one.
import 'dart:convert';
import 'dart:io';

import 'package:chatgpt_free/tools.dart';

void main(List<String> args) {
  final spec = jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;
  final functions = [
    for (final f in spec['functions'] as List)
      FunctionTool.fromJson(Map<String, dynamic>.from(f as Map)),
  ];
  final names = {for (final n in spec['names'] as List) '$n'};

  final out = [];
  for (final text in spec['cases'] as List) {
    final calls = detectToolCalls('$text', names, functions: functions);
    out.add(calls == null
        ? null
        : [for (final c in calls) {'name': c.name, 'arguments': c.arguments}]);
  }
  stdout.write(const JsonEncoder.withIndent('  ').convert(out));
}
