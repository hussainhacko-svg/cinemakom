import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import '../widgets/tv_focus_look.dart';

// The TV player's controls, from the Controls design: 40-tall chips at the
// top, 44-tall pills and round buttons at the bottom, all over the video's
// `night` veil. Focused: a `boothRaised` fill, the label at 600 and the 3 px
// `bulb` ring 2 px out (the TV system sheet); the `bulb` Play/Pause keeps its
// fill and gets a `cream` ring 3 px out.

/// The controls' see-through fill over the video.
final Color tvVeil = MarqueeColors.night.withValues(alpha: 0.6);

/// A chip of the top bar ("Arabic", "1080p", "1×", "Fit"): [label] is what
/// it shows, [name] what it reads as ("Subtitles: Arabic").
class TvPlayerChip extends StatelessWidget {
  const TvPlayerChip({
    super.key,
    required this.index,
    required this.name,
    required this.label,
    this.icon,
    this.onSelect,
    this.enabled = true,
  });

  final int index;
  final String name;
  final String label;
  final IconData? icon;
  final VoidCallback? onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _Pill(
    index: index,
    name: name,
    label: label,
    icon: icon,
    height: 40,
    padding: 16,
    onSelect: onSelect,
    enabled: enabled,
  );
}

/// A pill of the bottom row (Episodes, Next episode) or above the bar (Skip
/// intro, with a `cream` [outline] at 600; Start over).
class TvPlayerPill extends StatelessWidget {
  const TvPlayerPill({
    super.key,
    required this.index,
    required this.label,
    this.icon,
    this.iconAtEnd = false,
    this.outline = false,
    this.onSelect,
    this.onKey,
    this.autofocus = false,
    this.enabled = true,
  });

  final int index;
  final String label;
  final IconData? icon;
  final bool iconAtEnd;
  final bool outline;
  final VoidCallback? onSelect;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _Pill(
    index: index,
    name: label,
    label: label,
    icon: icon,
    iconAtEnd: iconAtEnd,
    height: 44,
    padding: outline ? 20 : 18,
    outline: outline,
    onSelect: onSelect,
    onKey: onKey,
    autofocus: autofocus,
    enabled: enabled,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.index,
    required this.name,
    required this.label,
    required this.height,
    required this.padding,
    this.icon,
    this.iconAtEnd = false,
    this.outline = false,
    this.onSelect,
    this.onKey,
    this.autofocus = false,
    this.enabled = true,
  });

  final int index;
  final String name;
  final String label;
  final double height;
  final double padding;
  final IconData? icon;
  final bool iconAtEnd;
  final bool outline;
  final VoidCallback? onSelect;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: name,
      enabled: enabled,
      onSelect: onSelect,
      onKey: onKey,
      autofocus: autofocus,
      builder: (context, focused) {
        final color = enabled ? MarqueeColors.cream : MarqueeColors.dustDim;
        final icon = this.icon == null
            ? null
            : Icon(this.icon, size: 18, color: color);
        return TvRing(
          on: focused,
          radius: TvRing.pill,
          gap: TvFocusStyle.buttonGap,
          child: Container(
            height: height,
            padding: EdgeInsetsDirectional.symmetric(horizontal: padding),
            decoration: ShapeDecoration(
              color: focused ? MarqueeColors.boothRaised : tvVeil,
              shape: StadiumBorder(
                side: BorderSide(
                  color: outline
                      ? MarqueeColors.cream
                      : MarqueeColors.velvetStrong,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null && !iconAtEnd) ...[
                  icon,
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: text.label
                      .withWeight(
                        outline || focused ? FontWeight.w600 : FontWeight.w500,
                      )
                      .copyWith(color: color, height: 1.2),
                ),
                if (icon != null && iconAtEnd) ...[
                  const SizedBox(width: 8),
                  icon,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A round button of the bottom row: back or forward 10 s (52, see-through,
/// the icon over "10"), or Play/Pause ([primary]: 64, `bulb`).
class TvRoundButton extends StatelessWidget {
  const TvRoundButton({
    super.key,
    required this.index,
    required this.label,
    required this.icon,
    this.caption,
    this.flip = false,
    this.primary = false,
    this.autofocus = false,
    this.onSelect,
  });

  final int index;
  final String label;
  final IconData icon;

  /// "10" under the icon.
  final String? caption;

  /// Mirrors the icon (forward 10 s uses back's arrow, turned round).
  final bool flip;
  final bool primary;
  final bool autofocus;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final size = primary ? 64.0 : 52.0;
    return TvFocusable(
      index: index,
      label: label,
      onSelect: onSelect,
      autofocus: autofocus,
      builder: (context, focused) {
        final color = primary ? MarqueeColors.onBulb : MarqueeColors.cream;
        Widget glyph = Icon(icon, size: primary ? 30 : 26, color: color);
        if (flip) glyph = Transform.flip(flipX: true, child: glyph);
        return TvRing(
          on: focused,
          radius: TvRing.pill,
          gap: primary ? 3 : TvFocusStyle.buttonGap,
          color: primary ? MarqueeColors.cream : MarqueeColors.bulb,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary
                  ? MarqueeColors.bulb
                  : focused
                  ? MarqueeColors.boothRaised
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                glyph,
                if (caption != null)
                  Text(
                    caption!,
                    textDirection: TextDirection.ltr,
                    style: MarqueeTvText.of(context).caption
                        .copyWith(fontSize: 11, height: 1, color: color)
                        .withWeight(FontWeight.w600),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A short note at the top of the player ("This device couldn't play 4K, so
/// it switched to 1080p."). Not focusable: it goes by itself.
class TvPlayerNote extends StatelessWidget {
  const TvPlayerNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.only(top: TvSpace.safeV + 56),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: MarqueeColors.booth,
          border: Border.all(color: MarqueeColors.velvet),
          borderRadius: const BorderRadius.all(MarqueeRadius.card),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: MarqueeTvText.of(context).body.copyWith(height: 1.35),
        ),
      ),
    ),
  );
}
