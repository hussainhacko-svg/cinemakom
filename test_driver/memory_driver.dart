// Driver for integration_test/memory_test.dart: writes the run to
// build/memory/<device>-<ui>-<scenario>.json and prints its table
// (tool/memory_report.dart; docs/MEMORY.md §4).
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import '../tool/memory_report.dart' as memory;

Future<void> main() => integrationDriver(
  timeout: const Duration(hours: 3),
  responseDataCallback: (data) async {
    final run = data?['memory'] as Map<String, dynamic>?;
    if (run == null) return;
    final slug = [run['device'], run['ui'], run['scenario']]
        .map(
          (part) => '$part'.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-'),
        )
        .join('-');
    final file = File('build/memory/$slug.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(run));
    stdout
      ..writeln(memory.report(run))
      ..writeln('Saved ${file.path}');
  },
);
