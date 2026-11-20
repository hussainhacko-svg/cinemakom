import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';

/// A titled group of [SettingsRow]s on a `booth` panel (DESIGN.md §5).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    // The heading is tracked caption text. Uppercase and tracking are for
    // Latin only (DESIGN.md §2, Arabic rules).
    final heading = text.eyebrow.copyWith(color: MarqueeColors.dust);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: MarqueeSpace.xs,
            bottom: MarqueeSpace.s,
          ),
          child: Semantics(
            header: true,
            child: Text(
              text.arabic ? title : title.toUpperCase(),
              style: heading,
            ),
          ),
        ),
        Material(
          color: MarqueeColors.booth,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(MarqueeRadius.card),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A 56-tall row: label at the start, value and chevron at the end.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final value = widget.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _focused ? MarqueeColors.boothRaised : null,
        border: _focused
            ? Border.all(color: MarqueeColors.bulb, width: 2)
            : null,
        borderRadius: const BorderRadius.all(MarqueeRadius.thumb),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: MarqueeSpace.l,
              vertical: MarqueeSpace.s,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: text.title
                        .copyWith(fontSize: 15)
                        .withWeight(FontWeight.w500),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: MarqueeSpace.m),
                  Text(
                    value,
                    style: text.label
                        .copyWith(color: MarqueeColors.dust)
                        .withWeight(FontWeight.w400),
                  ),
                ],
                const SizedBox(width: MarqueeSpace.s),
                const Icon(
                  Icons.chevron_right,
                  color: MarqueeColors.dust,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
