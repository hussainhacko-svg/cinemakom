import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';

/// A row in a TV panel (choices: subtitles, quality, language), item
/// [index] of its zone (the TV panel designs): 52 tall, radius 12, [label] at
/// 17 and [value] (a size, "1.2 GB") in `dust` at the end, or a longer
/// [detail] in `dust` under the label (the row is then [detailHeight] tall);
/// a `bulb` check when
/// [selected]. Focused: a `boothRaised` fill, the label at 600 and the ring
/// touching its edge. Selected and focused never look the same: the check is
/// the selection, the fill and ring are the focus. Disabled ones ("Too big")
/// stay visible in `dustDim` and the zone skips them.
class TvListRow extends StatelessWidget {
  const TvListRow({
    super.key,
    required this.index,
    required this.label,
    this.value,
    this.detail,
    this.selected = false,
    this.onSelect,
    this.enabled = true,
  });

  final int index;
  final String label;
  final String? value;
  final String? detail;
  final bool selected;
  final VoidCallback? onSelect;
  final bool enabled;

  static const double height = 52;
  static const double detailHeight = 72;
  static const double radius = 12;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: [label, ?value, ?detail].join(', '),
      enabled: enabled,
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: radius,
        child: Container(
          height: detail == null ? height : detailHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: focused ? context.palette.boothRaised : null,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body
                          .withWeight(FontWeight.w500)
                          .copyWith(
                            height: 1.2,
                            color: enabled
                                ? context.palette.cream
                                : context.palette.dustDim,
                          ),
                    ),
                    if (detail case final detail?) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption
                            .copyWith(fontSize: 15)
                            .withWeight(FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption
                        .copyWith(fontSize: 15)
                        .withWeight(FontWeight.w500),
                  ),
                ),
              ],
              if (selected) ...[
                const SizedBox(width: 12),
                Icon(Icons.check, size: 20, color: context.palette.bulb),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
