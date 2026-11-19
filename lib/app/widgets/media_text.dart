import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../l10n/app_localizations.dart';

/// Text helpers for titles in the UI language (DESIGN.md §2 metadata rules).
extension MediaText on BuildContext {
  bool get isArabicUi => Localizations.localeOf(this).languageCode == 'ar';

  /// The title in the UI language, falling back to the other one.
  String titleOf(MediaItem item) =>
      item.title.resolve(arabic: isArabicUi) ?? item.otherTitle ?? '';

  /// "2023 · Drama": year and first genre, for cards.
  String cardMeta(MediaItem item) => [
    if (item.year != null) '${item.year}',
    ?item.categories.firstOrNull?.resolve(arabic: isArabicUi),
  ].join(' · ');
}

/// "2h 46m", "2h", "47m".
String formatDuration(AppLocalizations l10n, Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return l10n.durationMinutes(d.inMinutes);
  if (minutes == 0) return l10n.durationHours(hours);
  return l10n.durationHoursMinutes(hours, minutes);
}

/// "Episode 7", "Episodes 7 & 8".
String episodeLabel(AppLocalizations l10n, EpisodeNumbering numbering) {
  final numbers = numbering.numbers;
  return numbers.length == 1
      ? l10n.episodeNumber(numbers.single)
      : l10n.episodeNumbers(numbers.join(l10n.episodeNumbersJoiner));
}
