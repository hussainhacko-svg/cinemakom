import 'dart:async';

import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every test file: a fresh flight recorder per test that doesn't print
/// (the app logs a lot; tests read [EventLog.instance.recent] instead).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => EventLog.instance = EventLog(echo: false));
  await testMain();
}
