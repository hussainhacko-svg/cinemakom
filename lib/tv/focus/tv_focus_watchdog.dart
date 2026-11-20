import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tv_nav.dart';

/// Debug check for R7 (docs/TV.md §5.1): focus never falls back to nothing
/// while a shown screen has something to focus. A few frames after each
/// focus change (a screen or a removed item gets time to pass focus on), it
/// reports a lost focus with the route and the last key. In a test that's a
/// failure, so a trap shows up there instead of on the sofa. Does nothing in
/// release builds.
class TvFocusWatchdog extends StatefulWidget {
  const TvFocusWatchdog({super.key, required this.child});

  final Widget child;

  /// Frames a focus change gets to settle before the check.
  static const graceFrames = 3;

  @override
  State<TvFocusWatchdog> createState() => _TvFocusWatchdogState();
}

class _TvFocusWatchdogState extends State<TvFocusWatchdog> {
  bool _pending = false;
  int _frames = 0;
  String _lastKey = 'none';
  String _lastRoute = 'unknown';

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      FocusManager.instance.addListener(_changed);
      HardwareKeyboard.instance.addHandler(_key);
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      FocusManager.instance.removeListener(_changed);
      HardwareKeyboard.instance.removeHandler(_key);
    }
    super.dispose();
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent) _lastKey = event.logicalKey.debugName ?? '?';
    return false;
  }

  void _changed() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus is TvItemNode && focus.context != null) {
      _lastRoute = ModalRoute.of(focus.context!)?.settings.name ?? _lastRoute;
    }
    if (_pending) {
      _frames = 0;
      return;
    }
    _pending = true;
    _frames = 0;
    _wait();
  }

  void _wait() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (++_frames < TvFocusWatchdog.graceFrames) {
        _wait();
        SchedulerBinding.instance.scheduleFrame();
        return;
      }
      _pending = false;
      _check();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _check() {
    if (!tvFocusIsLost()) return;
    final focusable = TvNavZone.live.any((z) => z.attached && z.canEnter);
    if (!focusable) return; // A loading screen has nothing to focus yet.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'TvFocusWatchdog: focus was lost while the screen had something '
          'to focus (docs/TV.md R7).\n'
          'Route: $_lastRoute. Last key: $_lastKey. '
          'Focus is on: ${FocusManager.instance.primaryFocus}.',
        ),
        library: 'tv focus',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
