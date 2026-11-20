import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';

/// Scrolls [context] comfortably into view when focused by D-pad on TV.
void tvEnsureVisible(BuildContext context, {double alignment = 0.35}) {
  Scrollable.ensureVisible(
    context,
    alignment: alignment,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
  );
}

/// A 10-foot TV page heading (no phone BackPill: TV remotes use Back).
class TvPageHeader extends StatelessWidget {
  const TvPageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final arabicTitle = MarqueeText.hasArabic(title);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        32,
        MarqueeSpace.l,
        32,
        MarqueeSpace.m,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                arabicTitle ? title : title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.displayLargeFor(title).copyWith(fontSize: 32),
              ),
            ),
          ),
          if (trailing case final t?) ...[
            const SizedBox(width: MarqueeSpace.m),
            t,
          ],
        ],
      ),
    );
  }
}

/// A TV section heading (non-focusable; "See all" lives as an end-of-row card).
class TvSectionHeader extends StatelessWidget {
  const TvSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final arabicTitle = MarqueeText.hasArabic(title);
    return Semantics(
      header: true,
      child: Text(
        arabicTitle ? title : title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: arabicTitle
            ? text.sectionTitle.copyWith(letterSpacing: 0, height: 1.4)
            : text.sectionTitle,
      ),
    );
  }
}

/// A spacious 10-foot filter pill with a 2 px `bulb` focus ring.
class TvPill extends StatefulWidget {
  const TvPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<TvPill> createState() => _TvPillState();
}

class _TvPillState extends State<TvPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Semantics(
      selected: widget.selected,
      button: true,
      excludeSemantics: true,
      label: widget.label,
      child: Material(
        color: widget.selected || _focused
            ? MarqueeColors.boothRaised
            : MarqueeColors.booth,
        shape: StadiumBorder(
          side: _focused
              ? const BorderSide(color: MarqueeColors.bulb, width: 2)
              : BorderSide(
                  color: widget.selected
                      ? MarqueeColors.velvetStrong
                      : MarqueeColors.velvet,
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFocusChange: (f) {
            setState(() => _focused = f);
            if (f) tvEnsureVisible(context, alignment: 0.4);
          },
          focusColor: Colors.transparent,
          child: Container(
            height: 40,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
            child: Center(
              widthFactor: 1,
              child: Text(
                widget.label,
                style: widget.selected || _focused
                    ? text.label.copyWith(
                        color: widget.selected
                            ? MarqueeColors.bulb
                            : MarqueeColors.cream,
                      )
                    : text.label
                          .copyWith(color: MarqueeColors.dust)
                          .withWeight(FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 10-foot segmented switcher for TV (Movies|Series, Continue|Favorites).
class TvSegmented<T> extends StatelessWidget {
  const TvSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < segments.length; i++) ...[
        if (i > 0) const SizedBox(width: MarqueeSpace.s),
        TvPill(
          label: segments[i].$2,
          selected: segments[i].$1 == selected,
          onTap: () => onChanged(segments[i].$1),
        ),
      ],
    ],
  );
}
