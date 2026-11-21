import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../focus/tv_panel.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_list_row.dart';

/// One choice in a [showTvChoicePanel]: a short [caption] at the end of the
/// row ("1.2 GB"), or a longer [detail] on a line under the label ("4K ·
/// about 10 GB per hour"). A disabled one ("2160p · Too big") stays visible
/// and can't be focused.
class TvChoice<T> {
  const TvChoice(
    this.value,
    this.label, {
    this.caption,
    this.detail,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? caption;
  final String? detail;
  final bool enabled;
}

/// A side panel with one row per choice, opened on the [selected] one
/// (docs/TV.md R11), as in the panel designs: an optional [eyebrow]
/// ("DOWNLOAD"), the [title], an optional [subtitle] ("Breaking Bad · Season
/// 2"), the rows, then at the bottom an optional [footer] ("3.8 GB free on
/// this TV") and "Back closes". OK picks and closes it; Back closes it with
/// `null`. Focus goes back to the control that opened it either way.
Future<T?> showTvChoicePanel<T>(
  BuildContext context, {
  required String title,
  required List<TvChoice<T>> choices,
  T? selected,
  String? eyebrow,
  String? subtitle,
  String? footer,
  double width = 400,
  double scrim = 0.72,
}) {
  final current = choices.indexWhere((c) => c.value == selected);
  return showTvSidePanel<T>(
    context,
    width: width,
    scrim: scrim,
    builder: (context, scroll) {
      final l10n = AppLocalizations.of(context);
      final text = MarqueeTvText.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null) ...[
            Text(
              text.arabic ? eyebrow : eyebrow.toUpperCase(),
              style: text.eyebrow,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            text.arabic ? title : title.toUpperCase(),
            style: text.panelTitle,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: text.caption),
          ],
          const SizedBox(height: 22),
          Expanded(
            child: TvZone.column(
              order: 0,
              initial: true,
              initialIndex: current < 0 ? 0 : current,
              keyline: 0,
              child: ListView.separated(
                controller: scroll,
                // Room for the rows' ring, which the list clips.
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: TvFocusStyle.ring,
                ),
                itemCount: choices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => TvListRow(
                  index: i,
                  label: choices[i].label,
                  value: choices[i].caption,
                  detail: choices[i].detail,
                  enabled: choices[i].enabled,
                  selected: i == current,
                  onSelect: () => Navigator.of(context).pop(choices[i].value),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (footer != null)
            Text(
              footer,
              style: text.caption.copyWith(color: context.palette.creamSoft),
            ),
          Text(l10n.tvBackCloses, style: text.caption),
        ],
      );
    },
  );
}
