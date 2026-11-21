import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'controls_overlay.dart' show withFocusRing;
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/models/playback_models.dart';
import '../up_next.dart';

/// "Up next · Season 2 · Episode 6" with Play now and Hide, in the bottom
/// end corner above the seek bar (PLAYER.md §7.7). It stays up when the
/// controls hide. During the countdown a ring fills around Play now's
/// icon; after 3 automatic episodes it asks "Still watching?".
class UpNextCard extends StatelessWidget {
  const UpNextCard({
    super.key,
    required this.next,
    required this.upNext,
    required this.onPlayNow,
    required this.onHide,
  });

  final Episode next;
  final UpNext upNext;
  final VoidCallback onPlayNow;
  final VoidCallback onHide;

  static const _imageWidth = 112.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final asking = upNext == UpNext.stillWatching;
    final episode =
        '${l10n.seasonNumber(next.season)} · '
        '${episodeLabel(l10n, next.numbering)}';
    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.bottomEnd,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            end: width >= 600 ? MarqueeSpace.xxxl : MarqueeSpace.l,
            bottom: 72,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.palette.booth,
                border: Border.all(color: context.palette.velvet),
                borderRadius: const BorderRadius.all(MarqueeRadius.card),
              ),
              child: Padding(
                padding: const EdgeInsets.all(MarqueeSpace.m),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: _imageWidth,
                      height: _imageWidth * 9 / 16,
                      child: MediaImage(
                        url: next.imageUrl,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: MarqueeSpace.m),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            asking
                                ? l10n.playerStillWatching
                                : l10n.playerUpNext,
                            style: asking
                                ? text.label
                                : text.caption.copyWith(
                                    color: context.palette.dust,
                                  ),
                          ),
                          Text(
                            episode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: asking ? text.caption : text.label,
                          ),
                          const SizedBox(height: MarqueeSpace.s),
                          Wrap(
                            spacing: MarqueeSpace.xs,
                            children: [
                              FilledButton.icon(
                                onPressed: onPlayNow,
                                icon: upNext == UpNext.countdown
                                    ? const _CountdownRing()
                                    : const Icon(Icons.play_arrow, size: 20),
                                label: Text(l10n.playerPlayNow),
                                style: withFocusRing(
                                  context,
                                  FilledButton.styleFrom(
                                    minimumSize: const Size(44, 40),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: onHide,
                                style: withFocusRing(
                                  context,
                                  TextButton.styleFrom(
                                    foregroundColor: context.palette.cream,
                                    minimumSize: const Size(44, 40),
                                  ),
                                ),
                                child: Text(l10n.playerHide),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring that fills over [upNextCountdown] around a play icon. Only a
/// picture: the controller's timer starts the next episode.
class _CountdownRing extends StatefulWidget {
  const _CountdownRing();

  @override
  State<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<_CountdownRing>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(
    vsync: this,
    duration: upNextCountdown,
  )..forward();

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? context.palette.onBulb;
    return SizedBox.square(
      dimension: 22,
      child: CustomPaint(
        painter: _RingPainter(_progress, color),
        child: Icon(Icons.play_arrow, size: 14, color: color),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas
      ..drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = color.withValues(alpha: 0.3),
      )
      ..drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress.value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
