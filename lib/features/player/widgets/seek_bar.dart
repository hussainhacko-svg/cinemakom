import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../data/models/playback_models.dart';
import 'seek_preview_frame.dart';

/// The seek bar: `bulb` played, `velvetStrong` buffered, `velvet` track,
/// with a `bulb` thumb (DESIGN.md §8). It always runs left to right, in
/// Arabic too (PLAYER.md §2). Only this widget repaints when the position
/// moves.
///
/// While dragging, or with the mouse over it, a bubble above the bar shows
/// the frame from [preview] and the time there (PLAYER.md §7.8); the time
/// alone when there's no frame.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.onSeek,
    this.onScrub,
    this.preview,
    this.semanticLabel,
  });

  final ValueListenable<Duration> position;
  final ValueListenable<Duration> buffered;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  /// While dragging: the time under the thumb, or `null` when the drag ends.
  final ValueChanged<Duration?>? onScrub;
  final SeekPreview? preview;
  final String? semanticLabel;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// The thumb's place while dragging, 0–1.
  double? _drag;

  /// The mouse's place over the bar, 0–1.
  double? _hover;

  static const _height = 44.0;

  Duration _at(double fraction) => widget.duration * fraction.clamp(0.0, 1.0);

  double _fraction(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _scrub(double fraction) {
    setState(() => _drag = fraction);
    widget.onScrub?.call(_at(fraction));
  }

  void _end() {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);
    widget.onScrub?.call(null);
    widget.onSeek(_at(drag));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.duration > Duration.zero;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final at = _drag ?? _hover;
          final bar = MouseRegion(
            onHover: enabled
                ? (e) =>
                      setState(() => _hover = _fraction(e.localPosition, width))
                : null,
            onExit: (_) {
              if (_hover != null) setState(() => _hover = null);
            },
            child: _bar(enabled, width),
          );
          // Always a Stack: wrapping the bar only while dragging would
          // rebuild its gesture detector and drop the drag.
          return Stack(
            clipBehavior: Clip.none,
            children: [
              bar,
              if (at != null && enabled)
                _Bubble(
                  at: _at(at),
                  x: _SeekBarPainter.thumbX(at, width),
                  barWidth: width,
                  frame: widget.preview?.frameAt(_at(at)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(bool enabled, double width) => Semantics(
    label: widget.semanticLabel,
    slider: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: enabled
          ? (d) => widget.onSeek(_at(_fraction(d.localPosition, width)))
          : null,
      onHorizontalDragStart: enabled
          ? (d) => _scrub(_fraction(d.localPosition, width))
          : null,
      onHorizontalDragUpdate: enabled
          ? (d) => _scrub(_fraction(d.localPosition, width))
          : null,
      onHorizontalDragEnd: enabled ? (_) => _end() : null,
      onHorizontalDragCancel: enabled ? _end : null,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SeekBarPainter(
              position: widget.position,
              buffered: widget.buffered,
              duration: widget.duration,
              drag: _drag,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The frame and the time above the bar, centred on [x] and kept within
/// the bar's width.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.at,
    required this.x,
    required this.barWidth,
    required this.frame,
  });

  final Duration at;
  final double x;
  final double barWidth;
  final SeekFrame? frame;

  static const _width = 120.0;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    final left = (x - _width / 2).clamp(
      0.0,
      (barWidth - _width).clamp(0.0, double.infinity),
    );
    return Positioned(
      left: left,
      bottom: _SeekBarState._height - MarqueeSpace.xs,
      width: _width,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (frame != null) ...[
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: MarqueeColors.velvet),
                  ),
                  borderRadius: BorderRadius.all(SeekPreviewFrame.radius),
                ),
                child: SeekPreviewFrame(frame: frame),
              ),
              const SizedBox(height: MarqueeSpace.xs),
            ],
            DecoratedBox(
              decoration: const BoxDecoration(
                color: MarqueeColors.booth,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MarqueeSpace.s,
                  vertical: 2,
                ),
                child: Text(
                  formatClock(at),
                  style: MarqueeText.of(context).label.copyWith(
                    color: MarqueeColors.cream,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.drag,
  }) : super(repaint: Listenable.merge([position, buffered]));

  final ValueListenable<Duration> position;
  final ValueListenable<Duration> buffered;
  final Duration duration;
  final double? drag;

  static const _track = 4.0;
  static const _thumb = 7.0;

  /// Where the thumb sits for [fraction] on a bar [width] wide.
  static double thumbX(double fraction, double width) =>
      _thumb + (width - _thumb * 2) * fraction;

  double _of(Duration d) => duration <= Duration.zero
      ? 0
      : (d.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final left = _thumb;
    final width = size.width - _thumb * 2;
    final played = drag ?? _of(position.value);
    final loaded = _of(buffered.value);
    final paint = Paint()
      ..strokeWidth = _track
      ..strokeCap = StrokeCap.round;

    void line(double from, double to, Color color) {
      if (to <= from) return;
      canvas.drawLine(
        Offset(left + width * from, y),
        Offset(left + width * to, y),
        paint..color = color,
      );
    }

    line(0, 1, MarqueeColors.velvet);
    line(0, loaded, MarqueeColors.velvetStrong);
    line(0, played, MarqueeColors.bulb);
    canvas.drawCircle(
      Offset(left + width * played, y),
      drag == null ? _thumb : _thumb + 2,
      Paint()..color = MarqueeColors.bulb,
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      old.drag != drag ||
      old.duration != duration ||
      old.position != position ||
      old.buffered != buffered;
}

/// "18:42", or "1:05:09" from an hour up. Western digits in every locale
/// (DESIGN.md §2).
String formatClock(Duration d) {
  final negative = d.isNegative;
  final t = d.abs();
  final h = t.inHours;
  final m = t.inMinutes.remainder(60);
  final s = t.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  final text = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return negative ? '−$text' : text;
}

/// Elapsed or remaining time, rebuilt only when the shown second changes.
class PlayerClock extends StatefulWidget {
  const PlayerClock({
    super.key,
    required this.position,
    required this.duration,
    this.remaining = false,
    this.style,
  });

  final ValueListenable<Duration> position;
  final Duration duration;
  final bool remaining;
  final TextStyle? style;

  @override
  State<PlayerClock> createState() => _PlayerClockState();
}

class _PlayerClockState extends State<PlayerClock> {
  late String _text = _format();

  String _format() {
    final p = widget.position.value;
    return widget.remaining
        ? formatClock(
            -(widget.duration - p < Duration.zero
                ? Duration.zero
                : widget.duration - p),
          )
        : formatClock(p);
  }

  void _update() {
    final text = _format();
    if (text != _text) setState(() => _text = text);
  }

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_update);
  }

  @override
  void didUpdateWidget(PlayerClock old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_update);
      widget.position.addListener(_update);
    }
    _text = _format();
  }

  @override
  void dispose() {
    widget.position.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    _text,
    textDirection: TextDirection.ltr,
    style: widget.style?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
