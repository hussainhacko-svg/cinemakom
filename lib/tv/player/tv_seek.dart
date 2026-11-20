import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../data/models/playback_models.dart';
import '../../features/player/player_labels.dart';
import '../../features/player/widgets/seek_preview_frame.dart';
import '../theme/tv_text.dart';

/// Seeking with the remote (docs/TV.md §8.1–8.2): each Left or Right moves a
/// target, not the video; the video goes there [settle] after the last key,
/// or at once on OK ([commit]). Held, the steps grow: 10 s, then 30 s after
/// 2 s, then 60 s after 5 s. A fresh press starts again at 10 s.
class TvScrub extends ChangeNotifier {
  TvScrub({required this.onCommit});

  final void Function(Duration to) onCommit;

  static const settle = Duration(milliseconds: 600);
  static const steps = [
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];
  static const stageAfter = [Duration(seconds: 2), Duration(seconds: 5)];

  Duration? _target;
  Duration _from = Duration.zero;
  int _stage = 0;
  Timer? _settle;
  final _stages = <Timer>[];

  /// Where the video will go; `null` while not seeking.
  Duration? get target => _target;

  /// Where it was when the seek started (the bar's tick, "was 19:26").
  Duration get from => _from;

  bool get active => _target != null;

  /// One step forward or back from the target ([position] when it starts).
  /// [repeat]: the key is held.
  void step({
    required bool forward,
    required bool repeat,
    required Duration position,
    required Duration duration,
  }) {
    if (_target == null) _from = _target = position;
    if (!repeat) _restartHold();
    final amount = steps[_stage];
    var to = _target! + (forward ? amount : -amount);
    if (to < Duration.zero) to = Duration.zero;
    if (duration > Duration.zero && to > duration) to = duration;
    _target = to;
    _settle?.cancel();
    _settle = Timer(settle, commit);
    notifyListeners();
  }

  void _restartHold() {
    for (final t in _stages) {
      t.cancel();
    }
    _stages.clear();
    _stage = 0;
    for (final (i, after) in stageAfter.indexed) {
      _stages.add(Timer(after, () => _stage = i + 1));
    }
  }

  /// Goes to the target now.
  void commit() {
    final to = _target;
    _clear();
    if (to != null) onCommit(to);
  }

  /// Stays where the video is.
  void cancel() => _clear();

  void _clear() {
    _settle?.cancel();
    for (final t in _stages) {
      t.cancel();
    }
    _stages.clear();
    _stage = 0;
    if (_target == null) return;
    _target = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _settle?.cancel();
    for (final t in _stages) {
      t.cancel();
    }
    super.dispose();
  }
}

/// "+5:00", "−0:30": how far a seek goes.
String seekDelta(Duration d) =>
    '${d.isNegative ? '−' : '+'}${formatClock(d.abs())}';

/// The bar itself (the TV player designs): a 6 dp track, the buffered part
/// in `velvetStrong`, played in `bulb` up to the seek target (else the
/// position), and a `bulb` thumb. While seeking, a `cream` tick marks where
/// the video was. Focused (an extra of TV-4, no artboard): the thumb grows to
/// 20 with a `cream` ring, like the `bulb` button's. Always left to right
/// (PLAYER.md §2); only this repaints as the video plays.
class TvSeekTrack extends StatelessWidget {
  const TvSeekTrack({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.scrub,
    this.focused = false,
    this.overVideo = false,
  });

  final ValueListenable<Duration> position;
  final ValueListenable<Duration> buffered;
  final Duration duration;
  final TvScrub scrub;
  final bool focused;

  /// Seeking with the controls hidden: the track is a `night` veil over the
  /// video and the thumb is 20.
  final bool overVideo;

  static const double height = 20;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrackPainter(
          repaint: Listenable.merge([position, buffered, scrub]),
          position: position,
          buffered: buffered,
          duration: duration,
          scrub: scrub,
          focused: focused,
          overVideo: overVideo,
        ),
      ),
    ),
  );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required Listenable repaint,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.scrub,
    required this.focused,
    required this.overVideo,
  }) : super(repaint: repaint);

  final ValueListenable<Duration> position;
  final ValueListenable<Duration> buffered;
  final Duration duration;
  final TvScrub scrub;
  final bool focused;
  final bool overVideo;

  double _at(Duration d) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (d.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const track = 6.0;
    final y = size.height / 2;
    final w = size.width;
    RRect bar(double to) => RRect.fromLTRBR(
      0,
      y - track / 2,
      w * to,
      y + track / 2,
      const Radius.circular(track / 2),
    );
    final shown = scrub.target ?? position.value;
    final paint = Paint();
    canvas
      ..drawRRect(
        bar(1),
        paint
          ..color = overVideo
              ? MarqueeColors.night.withValues(alpha: 0.6)
              : MarqueeColors.velvet,
      )
      ..drawRRect(
        bar(_at(buffered.value)),
        paint..color = MarqueeColors.velvetStrong,
      )
      ..drawRRect(bar(_at(shown)), paint..color = MarqueeColors.bulb);
    if (scrub.active) {
      final x = w * _at(scrub.from);
      canvas.drawRRect(
        RRect.fromLTRBR(
          x - 1.5,
          y - 6,
          x + 1.5,
          y + 6,
          const Radius.circular(2),
        ),
        paint..color = MarqueeColors.cream,
      );
    }
    final big = focused || overVideo || scrub.active;
    final r = big ? 10.0 : 8.0;
    final centre = Offset(w * _at(shown), y);
    canvas.drawCircle(centre, r, paint..color = MarqueeColors.bulb);
    if (focused) {
      canvas.drawCircle(
        centre,
        r + 2 + 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = MarqueeColors.cream,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.duration != duration ||
      old.focused != focused ||
      old.overVideo != overVideo ||
      old.position != position ||
      old.scrub != scrub;
}

/// Above the seek target (the Watching design): "+5:00" in a `bulb` pill,
/// then the frame there with a 2 px `cream` border, 99 tall at the video's
/// shape (owner's choice, docs/TV.md §2). The pill alone when the title has
/// no previews.
class TvSeekBubble extends StatelessWidget {
  const TvSeekBubble({
    super.key,
    required this.delta,
    this.frame,
    this.aspectRatio,
  });

  final Duration delta;
  final SeekFrame? frame;
  final double? aspectRatio;

  static const double frameHeight = 99;

  /// Its width with a frame (the frame's, as `SeekPreviewFrame` sizes it,
  /// plus the border), for placing it over the bar.
  static double widthFor(double? aspectRatio) =>
      (frameHeight - 4) * (aspectRatio ?? 16 / 9).clamp(1.2, 2.5) + 4;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    final frame = this.frame;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: const ShapeDecoration(
            color: MarqueeColors.bulb,
            shape: StadiumBorder(),
          ),
          child: Text(
            seekDelta(delta),
            textDirection: TextDirection.ltr,
            style: text.caption
                .withWeight(FontWeight.w600)
                .copyWith(color: MarqueeColors.onBulb, height: 1),
          ),
        ),
        if (frame != null) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: MarqueeColors.cream, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: SeekPreviewFrame(
                frame: frame,
                aspectRatio: aspectRatio,
                height: frameHeight - 4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The track with the bubble over the seek target while seeking, kept
/// inside the bar's width.
class TvSeekBar extends StatelessWidget {
  const TvSeekBar({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.scrub,
    this.preview,
    this.aspectRatio,
    this.focused = false,
    this.overVideo = false,
    this.bubble = true,
  });

  final ValueListenable<Duration> position;
  final ValueListenable<Duration> buffered;
  final Duration duration;
  final TvScrub scrub;

  /// False while the controls are hidden (the bar over the video has it).
  final bool bubble;
  final SeekPreview? preview;
  final double? aspectRatio;
  final bool focused;
  final bool overVideo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          TvSeekTrack(
            position: position,
            buffered: buffered,
            duration: duration,
            scrub: scrub,
            focused: focused,
            overVideo: overVideo,
          ),
          ListenableBuilder(
            listenable: scrub,
            builder: (context, _) {
              final target = scrub.target;
              if (target == null || !bubble) return const SizedBox.shrink();
              final frame = preview?.frameAt(target);
              final bubbleWidth = frame == null
                  ? 72.0
                  : TvSeekBubble.widthFor(aspectRatio);
              final total = duration.inMilliseconds;
              final x = total <= 0
                  ? 0.0
                  : width * (target.inMilliseconds / total).clamp(0.0, 1.0);
              return Positioned(
                left: (x - bubbleWidth / 2).clamp(
                  0.0,
                  (width - bubbleWidth).clamp(0.0, width),
                ),
                bottom: TvSeekTrack.height + 6,
                width: bubbleWidth,
                child: TvSeekBubble(
                  delta: target - scrub.from,
                  frame: frame,
                  aspectRatio: aspectRatio,
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

/// The time under the bar while seeking with the controls hidden: "24:26 ·
/// was 19:26", and the length at the other end (the Watching design).
class TvSeekTimes extends StatelessWidget {
  const TvSeekTimes({super.key, required this.scrub, required this.duration});

  final TvScrub scrub;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final style = text.caption
        .copyWith(fontSize: 15, color: MarqueeColors.cream)
        .withWeight(FontWeight.w500);
    return ListenableBuilder(
      listenable: scrub,
      builder: (context, _) {
        final target = scrub.target ?? Duration.zero;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Text(formatClock(target), style: style),
              Text(
                ' · ${l10n.tvPlayerWas(formatClock(scrub.from))}',
                style: style.copyWith(color: MarqueeColors.creamSoft),
              ),
              const Spacer(),
              Text(
                formatClock(duration),
                style: style.copyWith(color: MarqueeColors.creamSoft),
              ),
            ],
          ),
        );
      },
    );
  }
}
