import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';
import 'tv_image.dart';
import 'tv_steady_text.dart';

// The tabs' rows and tiles (the TV Library, Downloads, Search and Settings
// designs). Focused, each gets a `boothRaised` fill and the 3 px `bulb` ring
// (touching a row's edge, 2 px out from a pill), as on the system sheet.

/// A title's row: a `booth` card (radius 12, padding 8) with a 56 × 84
/// poster, then [title] (18, 600) and [lines] under it; [bar] adds a 300 dp
/// progress bar, [trailing] sits at its end (a chevron). Item [index] of
/// its zone; the Library's and Downloads' rows put their buttons beside it.
class TvShelfRow extends StatelessWidget {
  const TvShelfRow({
    super.key,
    required this.index,
    required this.label,
    required this.title,
    required this.onSelect,
    this.posterUrl,
    this.lines = const [],
    this.bar,
    this.barColor = MarqueeColors.bulb,
    this.trailing,
  });

  final int index;
  final String label;
  final String title;
  final VoidCallback onSelect;
  final String? posterUrl;

  /// Caption lines under the title: the first in `creamSoft`, the rest in
  /// `dust`.
  final List<String> lines;
  final double? bar;
  final Color barColor;
  final Widget? trailing;

  static const double posterWidth = 56;
  static const double posterHeight = 84;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    final bar = this.bar;
    return TvFocusable(
      index: index,
      label: label,
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 12,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: posterWidth,
                height: posterHeight,
                child: TvImage(url: posterUrl, radius: 6),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.title.copyWith(height: 1.2),
                    ),
                    for (final (i, line) in lines.indexed)
                      if (line.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.caption.copyWith(
                            height: 1.2,
                            color: i == 0
                                ? MarqueeColors.creamSoft
                                : MarqueeColors.dust,
                          ),
                        ),
                        if (i == 0 && bar != null) ...[
                          const SizedBox(height: 7),
                          SizedBox(
                            width: 300,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: bar,
                                minHeight: 4,
                                color: barColor,
                                backgroundColor: MarqueeColors.velvet,
                              ),
                            ),
                          ),
                        ],
                      ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A `booth` tile with its [label] (the genre grid): 72 tall, radius 12.
class TvTile extends StatelessWidget {
  const TvTile({
    super.key,
    required this.index,
    required this.label,
    required this.onSelect,
  });

  final int index;
  final String label;
  final VoidCallback onSelect;

  static const double height = 72;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: label,
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 12,
        child: Container(
          height: height,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            color: focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
            border: Border.all(
              color: focused ? MarqueeColors.boothRaised : MarqueeColors.velvet,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.body.withWeight(FontWeight.w600).copyWith(height: 1.2),
          ),
        ),
      ),
    );
  }
}

/// One side of a segmented control (the Library design): a 44-tall pill
/// on the `booth` track, `boothRaised` with a `cream` label at 600 when
/// [selected]; focused adds the ring. Moving onto it picks it ([onFocus]),
/// as the tabs do.
class TvSegment extends StatelessWidget {
  const TvSegment({
    super.key,
    required this.index,
    required this.label,
    required this.selected,
    required this.onFocus,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: label,
      onFocus: onFocus,
      onSelect: onFocus,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: TvRing.pill,
        gap: TvFocusStyle.buttonGap,
        child: Container(
          height: 44,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected || focused ? MarqueeColors.boothRaised : null,
            shape: const StadiumBorder(),
          ),
          child: TvSteadyText(
            label,
            style: text.label
                .withWeight(selected ? FontWeight.w600 : FontWeight.w500)
                .copyWith(
                  color: selected ? MarqueeColors.cream : MarqueeColors.dust,
                ),
          ),
        ),
      ),
    );
  }
}

/// The segments' `booth` track (padding 4, a pill).
class TvSegmentTrack extends StatelessWidget {
  const TvSegmentTrack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: MarqueeColors.booth,
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            c,
          ],
        ],
      ),
    ),
  );
}

/// A settings row (the TV Settings design): 56 tall, `booth` with a `velvet`
/// edge, radius 12; the label at 17, the value in `dust` and a chevron at
/// the end. Focused: `boothRaised`, the label at 600, the value in `cream`.
class TvSettingsRow extends StatelessWidget {
  const TvSettingsRow({
    super.key,
    required this.index,
    required this.label,
    required this.onSelect,
    this.value,
  });

  final int index;
  final String label;
  final String? value;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    final value = this.value;
    return TvFocusable(
      index: index,
      label: value == null ? label : '$label, $value',
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 12,
        child: Container(
          height: 56,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
            border: Border.all(
              color: focused ? MarqueeColors.boothRaised : MarqueeColors.velvet,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.body
                      .withWeight(focused ? FontWeight.w600 : FontWeight.w500)
                      .copyWith(height: 1.2),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 14),
                Text(
                  value,
                  style: text.label
                      .withWeight(FontWeight.w500)
                      .copyWith(
                        color: focused
                            ? MarqueeColors.cream
                            : MarqueeColors.dust,
                      ),
                ),
              ],
              const SizedBox(width: 14),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: MarqueeColors.dust,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty shelves say what goes there, centred (DESIGN.md §8).
class TvEmpty extends StatelessWidget {
  const TvEmpty(this.message, {super.key, this.action});

  final String message;

  /// A button under the text ("Browse Home"), in its own zone.
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: TvSpace.safeH * 2,
      vertical: 48,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: MarqueeTvText.of(context).body
              .copyWith(color: MarqueeColors.dust),
        ),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}
