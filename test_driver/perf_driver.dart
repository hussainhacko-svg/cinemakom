// Driver for integration_test/scroll_perf_test.dart: prints each scenario's
// frame build (UI thread) and raster times against a frame budget, and
// writes the raw summary to build/scroll_perf.json.
//
// The budget defaults to 120 Hz; pass --dart-define=PERF_HZ=60 (or 90).
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

const _hz = int.fromEnvironment('PERF_HZ', defaultValue: 120);

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final budgetUs = 1e6 / _hz;
    stdout.writeln('Frame budget ${(budgetUs / 1000).toStringAsFixed(2)} ms '
        '($_hz Hz)');
    for (final MapEntry(:key, :value) in data.entries) {
      final summary = value as Map<String, dynamic>;
      final build = _times(summary['frame_build_times']);
      final raster = _times(summary['frame_rasterizer_times']);
      stdout.writeln('$key: ${build.length} frames');
      stdout.writeln('  UI     ${_stats(build, budgetUs)}');
      stdout.writeln('  raster ${_stats(raster, budgetUs)}');
    }
    await File('build/scroll_perf.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  },
);

List<int> _times(Object? list) =>
    [for (final t in (list as List? ?? const [])) (t as num).toInt()]..sort();

String _stats(List<int> us, double budgetUs) {
  if (us.isEmpty) return 'no frames';
  String ms(num v) => (v / 1000).toStringAsFixed(2);
  int at(double p) => us[((us.length - 1) * p).round()];
  final over = us.where((t) => t > budgetUs).length;
  final avg = us.reduce((a, b) => a + b) / us.length;
  return 'avg ${ms(avg)}  p90 ${ms(at(.9))}  p99 ${ms(at(.99))}  '
      'max ${ms(us.last)} ms  over budget $over '
      '(${(100 * over / us.length).toStringAsFixed(1)}%)';
}
