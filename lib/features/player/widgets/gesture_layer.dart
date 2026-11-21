import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../player_controller.dart';
import '../player_state.dart';

/// Touch gestures over the video on phones (PLAYER.md §9.1). The only place
/// that changes brightness and volume.
///
/// | Gesture | Action |
/// |---|---|
/// | Tap | [onTap] (show or hide the controls) |
/// | Double-tap the left / right third | −10 s / +10 s; more taps add up |
/// | Vertical drag, left / right half | Brightness / volume |
/// | Two fingers (a pinch) | Nothing (the owner removed pinch to fill) |
///
/// Sides are physical, in Arabic too (PLAYER.md §2). Drags that start
/// within [edge] of the screen's edge are left to the system (back gesture,
/// notification shade). While [locked], a tap only calls [onLockedTap].
class GestureLayer extends StatefulWidget {
  const GestureLayer({
    super.key,
    required this.controller,
    required this.state,
    required this.locked,
    required this.onTap,
    required this.onLockedTap,
    required this.child,
  });

  final PlayerController controller;
  final PlayerState state;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onLockedTap;

  /// The controls, under the gestures' feedback.
  final Widget child;

  static const edge = 24.0;
  static const seekStep = Duration(seconds: 10);

  /// A second tap on the same side within this is a double tap. A single
  /// tap on a side waits this long before toggling the controls.
  static const doubleTapWindow = Duration(milliseconds: 250);

  /// Taps on the same side keep adding 10 s while they come this close.
  static const streakWindow = Duration(milliseconds: 700);

  @override
  State<GestureLayer> createState() => _GestureLayerState();
}

enum _Side { left, right }

enum _Drag { none, ignored, brightness, volume }

class _GestureLayerState extends State<GestureLayer> {
  // Double taps.
  Timer? _singleTap;
  _Side? _pendingSide;
  Timer? _streak;
  _Side? _streakSide;
  int _streakSeconds = 0;

  // Drags and pinches.
  _Drag _drag = _Drag.none;

  /// Where the finger came down. A scale gesture only starts once it has
  /// moved past the slop, so its own start point is too late for the edge
  /// check and the swipe's length.
  Offset _down = Offset.zero;
  Offset _start = Offset.zero;
  double _levelFrom = 0;
  double? _level;
  bool _levelIsBrightness = false;
  Timer? _levelHide;

  // The device's levels, read up front so a swipe starts at once.
  double _brightness = 0.5;
  double _volume = 0.5;
  bool _brightnessChanged = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readLevels());
  }

  Future<void> _readLevels() async {
    try {
      _brightness = await ScreenBrightness.instance.application;
    } on Object {
      // Not available (tests): start from the middle.
    }
    try {
      VolumeController.instance.showSystemUI = false;
      _volume = await VolumeController.instance.getVolume();
    } on Object {
      // Not available.
    }
  }

  @override
  void dispose() {
    _singleTap?.cancel();
    _streak?.cancel();
    _levelHide?.cancel();
    // Brightness is the app's own, only while the player is open.
    if (_brightnessChanged) {
      unawaited(
        ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
          (Object _) {},
        ),
      );
    }
    super.dispose();
  }

  _Side? _sideOf(double x, double width) => x < width / 3
      ? _Side.left
      : x > width * 2 / 3
      ? _Side.right
      : null;

  // ---------------------------------------------------------------------------
  // Taps

  void _onTapUp(TapUpDetails d) {
    if (widget.locked) return widget.onLockedTap();
    final side = _sideOf(d.localPosition.dx, context.size!.width);
    if (side == null) {
      _singleTap?.cancel();
      return widget.onTap();
    }
    final second = _singleTap?.isActive == true && _pendingSide == side;
    final streak = _streak?.isActive == true && _streakSide == side;
    _singleTap?.cancel();
    if (second || streak) return _seekTap(side);
    _pendingSide = side;
    _singleTap = Timer(GestureLayer.doubleTapWindow, widget.onTap);
  }

  void _seekTap(_Side side) {
    if (_streakSide != side || _streak?.isActive != true) _streakSeconds = 0;
    _streakSide = side;
    _streakSeconds += GestureLayer.seekStep.inSeconds;
    final step = side == _Side.left
        ? -GestureLayer.seekStep
        : GestureLayer.seekStep;
    unawaited(widget.controller.seekBy(step));
    _streak?.cancel();
    _streak = Timer(GestureLayer.streakWindow, () {
      if (mounted) setState(() => _streakSide = null);
    });
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Drags

  void _onScaleStart(ScaleStartDetails d) {
    _drag = _Drag.none;
    if (widget.locked) {
      _drag = _Drag.ignored;
      return;
    }
    // Two fingers do nothing: no pinch to fill (owner, 2026-11-22).
    if (d.pointerCount >= 2) {
      _drag = _Drag.ignored;
      return;
    }
    final size = context.size!;
    final p = _down;
    const e = GestureLayer.edge;
    if (p.dx < e ||
        p.dy < e ||
        p.dx > size.width - e ||
        p.dy > size.height - e) {
      _drag = _Drag.ignored;
    }
    _start = p;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_drag == _Drag.ignored) return;
    if (d.pointerCount >= 2) {
      _drag = _Drag.ignored;
      return;
    }
    final size = context.size!;
    final delta = d.localFocalPoint - _start;
    if (_drag == _Drag.none) {
      if (delta.distance < 12) return;
      widget.controller.noteActivity();
      // Sideways swipes do nothing (the owner chose not to seek with them).
      if (delta.dx.abs() > delta.dy.abs()) {
        _drag = _Drag.ignored;
        return;
      } else {
        _drag = _start.dx < size.width / 2 ? _Drag.brightness : _Drag.volume;
        _levelIsBrightness = _drag == _Drag.brightness;
        _levelFrom = _levelIsBrightness ? _brightness : _volume;
        _levelHide?.cancel();
      }
    }
    switch (_drag) {
      case _Drag.brightness || _Drag.volume:
        final level = (_levelFrom - delta.dy / (size.height * 0.75)).clamp(
          0.0,
          1.0,
        );
        setState(() => _level = level);
        _apply(level);
      default:
        break;
    }
  }

  void _apply(double level) {
    if (_drag == _Drag.brightness) {
      _brightness = level;
      _brightnessChanged = true;
      unawaited(
        ScreenBrightness.instance
            .setApplicationScreenBrightness(level)
            .catchError((Object _) {}),
      );
    } else {
      _volume = level;
      unawaited(
        VolumeController.instance.setVolume(level).catchError((Object _) {}),
      );
    }
  }

  void _onScaleEnd(ScaleEndDetails _) {
    switch (_drag) {
      case _Drag.brightness || _Drag.volume:
        _levelHide = Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _level = null);
        });
      default:
        break;
    }
    _drag = _Drag.none;
  }

  @override
  Widget build(BuildContext context) {
    final level = _level;
    final streak = _streak?.isActive == true ? _streakSide : null;
    return Listener(
      onPointerDown: (e) => _down = e.localPosition,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (streak != null)
              IgnorePointer(
                child: _SeekTaps(side: streak, seconds: _streakSeconds),
              ),
            if (level != null)
              IgnorePointer(
                child: _Level(value: level, brightness: _levelIsBrightness),
              ),
          ],
        ),
      ),
    );
  }
}

/// A round mark on the tapped side: the arrows and "+30 s".
class _SeekTaps extends StatelessWidget {
  const _SeekTaps({required this.side, required this.seconds});

  final _Side side;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final left = side == _Side.left;
    // Physical sides, in Arabic too.
    return Align(
      alignment: Alignment(left ? -0.7 : 0.7, 0),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: context.palette.night.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              left ? Icons.fast_rewind : Icons.fast_forward,
              size: 32,
              color: context.palette.cream,
            ),
            const SizedBox(height: MarqueeSpace.xs),
            Text(
              l10n.playerSeekAmount(
                // A left-to-right isolate keeps the sign in front in Arabic.
                '\u2066${left ? '−' : '+'}$seconds\u2069',
              ),
              style: MarqueeText.of(context).label,
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim vertical level with its icon: brightness on the left, volume on
/// the right (physical sides).
class _Level extends StatelessWidget {
  const _Level({required this.value, required this.brightness});

  final double value;
  final bool brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final icon = brightness
        ? Icons.brightness_6_outlined
        : value == 0
        ? Icons.volume_off_outlined
        : Icons.volume_up_outlined;
    return Align(
      alignment: Alignment(brightness ? -0.8 : 0.8, 0),
      child: Semantics(
        label: brightness ? l10n.playerBrightness : l10n.playerVolume,
        value: '${(value * 100).round()}%',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.palette.night.withValues(alpha: 0.7),
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MarqueeSpace.s,
              vertical: MarqueeSpace.m,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 6,
                  height: 120,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.palette.velvet,
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: value,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.palette.bulb,
                            borderRadius: BorderRadius.all(Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: MarqueeSpace.s),
                Icon(icon, size: 20, color: context.palette.cream),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
