import 'dart:ui';

import 'package:cinemakom/app/widgets/broken_part.dart';
import 'package:cinemakom/core/diagnostics/diagnostics.dart';
import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A frame of [total] ms, [build] of them building.
FrameTiming frame(int total, {int build = 0}) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: build * 1000,
  rasterStart: build * 1000,
  rasterFinish: total * 1000,
  rasterFinishWallTime: total * 1000,
);

void main() {
  late EventLog log;
  setUp(() => EventLog.instance = log = EventLog(echo: false));
  List<String> lines(String tag) => [
    for (final e in log.recent)
      if (e.tag == tag) e.message,
  ];

  group('a frozen event loop', () {
    late Duration now;
    late bool front;
    final lags = <Duration>[];
    late LagWatch watch;
    setUp(() {
      now = Duration.zero;
      front = true;
      lags.clear();
      watch = LagWatch(
        elapsed: () => now,
        inFront: () => front,
        onLag: lags.add,
      );
    });

    void beatAt(int ms) {
      now = Duration(milliseconds: ms);
      watch.check();
    }

    test('beats on time: nothing', () {
      for (var t = 0; t <= 5000; t += 250) {
        beatAt(t);
      }
      expect(lags, isEmpty);
    });

    test('a beat 1.75 s late: blocked for 1.75 s', () {
      beatAt(0);
      beatAt(250);
      beatAt(2250);
      expect(lags, [const Duration(milliseconds: 1750)]);
    });

    test('a little late is no freeze', () {
      beatAt(0);
      beatAt(1200); // 950 ms late
      expect(lags, isEmpty);
    });

    test('the device asleep (minutes) is no freeze', () {
      beatAt(0);
      beatAt(10 * 60 * 1000);
      expect(lags, isEmpty);
    });

    test('in the background is no freeze', () {
      beatAt(0);
      front = false;
      beatAt(5000);
      expect(lags, isEmpty);
    });

    test('logged at once, urgent', () {
      final w = LagWatch(elapsed: () => now, inFront: () => true);
      now = Duration.zero;
      w.check();
      now = const Duration(seconds: 3);
      w.check();
      expect(lines('freeze').single, 'the app was unresponsive for 2750 ms');
    });
  });

  group('slow frames', () {
    late Duration now;
    late FreezeWatch watch;
    setUp(() {
      now = Duration.zero;
      watch = FreezeWatch(elapsed: () => now, inFront: () => true);
    });

    test('a slow frame, with its build and raster time', () {
      watch.onTimings([frame(16), frame(900, build: 850), frame(20)]);
      expect(lines('freeze'), ['a frame took 900 ms (build 850, raster 50)']);
    });

    test('a run of slow frames: one line, then how many more', () {
      for (var i = 0; i < 5; i++) {
        watch.onTimings([frame(800)]);
        now += const Duration(milliseconds: 300);
      }
      expect(lines('freeze'), hasLength(1));
      now += const Duration(seconds: 3);
      watch.onTimings([frame(1000)]);
      expect(lines('freeze').last, endsWith('(4 more since)'));
    });

    test('in the background: nothing', () {
      FreezeWatch(inFront: () => false).onTimings([frame(5000)]);
      expect(lines('freeze'), isEmpty);
    });
  });

  group('uncaught errors', () {
    late FlutterExceptionHandler? flutterBefore;
    late ErrorCallback? platformBefore;
    setUp(() {
      flutterBefore = FlutterError.onError;
      platformBefore = PlatformDispatcher.instance.onError;
      FlutterError.onError = (_) {};
      installErrorCapture();
    });
    tearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
    });

    test('a framework error: what, where, and the stack', () {
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('no frame'),
          library: 'widgets library',
          context: ErrorDescription('while building TvPlayerScreen'),
          stack: StackTrace.fromString('#0 build (tv_player_screen.dart:1)'),
        ),
      );
      final m = lines('error').single;
      expect(m, contains('Bad state: no frame'));
      expect(m, contains('in widgets library'));
      expect(m, contains('while building TvPlayerScreen'));
      expect(m, contains('tv_player_screen.dart:1'));
    });

    test('an error nobody awaited is logged and handled', () {
      final handled = PlatformDispatcher.instance.onError!(
        Exception('lost'),
        StackTrace.fromString('#0 somewhere'),
      );
      expect(handled, isTrue);
      expect(lines('error').single, contains('uncaught: Exception: lost'));
    });

    test('the handler that was there still runs', () {
      final seen = <FlutterErrorDetails>[];
      FlutterError.onError = seen.add;
      installErrorCapture();
      FlutterError.onError!(FlutterErrorDetails(exception: 'x'));
      expect(seen, hasLength(1));
      expect(lines('error'), hasLength(1));
    });
  });

  testWidgets('a part that fails to build shows the background', (
    tester,
  ) async {
    await tester.pumpWidget(const BrokenPart());
    expect(find.byType(BrokenPart), findsOneWidget);
  });
}
