import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/app_dirs.dart';
import '../platform/app_info.dart';
import 'event_log.dart';
import 'memory.dart';

/// Where the log files are. On Android it's the app's external folder,
/// which `adb pull` reaches without root
/// (`/sdcard/Android/data/<package>/files/logs`); on desktop the state
/// folder (`~/.local/state/<id>/logs`, Local AppData on Windows).
Future<Directory> logDirectory() async {
  if (AppDirs.current case final dirs?) {
    return Directory('${dirs.state}${Platform.pathSeparator}logs');
  }
  Directory? base;
  if (Platform.isAndroid) {
    try {
      base = await getExternalStorageDirectory();
    } on Object {
      base = null;
    }
  }
  base ??= await getApplicationSupportDirectory();
  return Directory('${base.path}/logs');
}

/// Starts the recorder, once, before `runApp`: the files with a header
/// saying what app and device this is, every uncaught error, and freezes.
/// [ui] names the UI (`phone`, `tv`, `desktop`). Never throws, and never
/// holds up the start for long.
Future<void> startDiagnostics({required String ui}) async {
  installErrorCapture();
  FreezeWatch.instance.start();
  _LifecycleLog.start();
  MemoryLog.start();
  try {
    final info = await readAppInfo().timeout(const Duration(seconds: 2));
    final header = [
      'Cinemakom ${info.version} · $ui · ${info.device}',
      'Dart ${Platform.version.split(' ').first} · '
          '${PlatformDispatcher.instance.locale.toLanguageTag()} · '
          'started ${DateTime.now()}',
    ].join('\n');
    await EventLog.instance
        .attach(await logDirectory(), header: header)
        .timeout(const Duration(seconds: 2));
    logEvent('app', 'started ($ui, ${info.version})');
  } on Object catch (e) {
    logEvent('log', 'no log file: $e');
  }
}

/// Every uncaught error goes in the log, written at once (the app may be
/// about to go). (What a widget that fails to build shows is the app's:
/// `BrokenPart`.)
void installErrorCapture() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    logEvent('error', describeFlutterError(details), urgent: true);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logEvent('error', 'uncaught: $error\n$stack', urgent: true);
    // Handled: an error nobody awaited is logged, not a crash.
    return true;
  };
}

/// The error, where it happened (the widget or library), and the stack.
String describeFlutterError(FlutterErrorDetails details) {
  final context = details.context?.toDescription();
  return [
    details.exceptionAsString(),
    if (details.library != null) 'in ${details.library}',
    ?context,
    if (details.stack != null) '${details.stack}'.trimRight(),
  ].join('\n');
}

/// Notices when the app stops responding: frames that take too long
/// ([slowFrame]), and stretches where the Dart code couldn't run at all
/// ([LagWatch]). Only while the app is in front: a phone in a pocket or a
/// TV asleep pauses timers too, and that's no freeze.
class FreezeWatch {
  FreezeWatch({
    this.slowFrame = const Duration(milliseconds: 700),
    LagWatch? lag,
    Duration Function()? elapsed,
    bool Function()? inFront,
  }) : lag = lag ?? LagWatch(),
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedFn,
       _inFront = inFront ?? (() => _appInFront);

  static final instance = FreezeWatch();

  final Duration slowFrame;
  final LagWatch lag;

  Timer? _beat;
  bool _started = false;

  /// At most one slow-frame line every [_frameGap]; the others are counted.
  static const _frameGap = Duration(seconds: 2);
  final Duration Function() _elapsed;
  final bool Function() _inFront;
  Duration? _lastFrameLine;
  int _unreported = 0;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    _beat = Timer.periodic(lag.interval, (_) => lag.check());
  }

  /// Logs the slow ones of [timings].
  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (t.totalSpan < slowFrame || !_inFront()) continue;
      final now = _elapsed();
      final last = _lastFrameLine;
      if (last != null && now - last < _frameGap) {
        _unreported++;
        continue;
      }
      _lastFrameLine = now;
      final more = _unreported == 0 ? '' : ' ($_unreported more since)';
      _unreported = 0;
      logEvent(
        'freeze',
        'a frame took ${t.totalSpan.inMilliseconds} ms (build '
            '${t.buildDuration.inMilliseconds}, raster '
            '${t.rasterDuration.inMilliseconds})$more',
      );
    }
  }

  void stop() {
    _beat?.cancel();
    if (_started) SchedulerBinding.instance.removeTimingsCallback(onTimings);
    _started = false;
  }
}

bool get _appInFront {
  final state = SchedulerBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// A heartbeat on the app's event loop: when a beat comes more than
/// [threshold] late, the loop was blocked that long (a freeze: nothing ran,
/// no key was handled). [check] runs every [interval].
class LagWatch {
  LagWatch({
    this.interval = const Duration(milliseconds: 250),
    this.threshold = const Duration(seconds: 1),
    this.longest = const Duration(minutes: 5),
    Duration Function()? elapsed,
    bool Function()? inFront,
    void Function(Duration blocked)? onLag,
  }) : _elapsed = elapsed ?? (Stopwatch()..start()).elapsedFn,
       _inFront = inFront ?? (() => _appInFront),
       _onLag = onLag ?? _log;

  final Duration interval;
  final Duration threshold;

  /// Longer gaps are the device sleeping (or a debugger), not a freeze.
  final Duration longest;
  final Duration Function() _elapsed;
  final bool Function() _inFront;
  final void Function(Duration blocked) _onLag;
  Duration? _last;

  static void _log(Duration blocked) => logEvent(
    'freeze',
    'the app was unresponsive for ${blocked.inMilliseconds} ms',
    urgent: true,
  );

  /// One beat: reports the time since the last one beyond [interval].
  void check() {
    final now = _elapsed();
    final last = _last;
    _last = now;
    if (last == null || !_inFront()) return;
    final blocked = now - last - interval;
    if (blocked < threshold || blocked > longest) return;
    _onLag(blocked);
  }
}

extension on Stopwatch {
  Duration Function() get elapsedFn =>
      () => elapsed;
}

/// The app's lifecycle in the log; going to the background writes the
/// file (the system may end the app there).
abstract final class _LifecycleLog {
  static AppLifecycleListener? _listener;

  static void start() {
    _listener ??= AppLifecycleListener(
      onStateChange: (state) {
        final away =
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached;
        logEvent('app', state.name, urgent: away);
      },
    );
  }
}
