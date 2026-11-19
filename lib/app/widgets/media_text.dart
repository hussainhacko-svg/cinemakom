import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../l10n/app_localizations.dart';

/// Text helpers for titles in the UI language (DESIGN.md §2 metadata rules).
extension MediaText on BuildContext {
  bool get isArabicUi => Localizations.localeOf(this).languageCode == 'ar';

  /// The title in the UI language, falling back to the other one.
  String titleOf(MediaItem item) =>
      item.title.resolve(arabic: isArabicUi) ?? item.otherTitle ?? '';

  /// [parts] joined with " · ". In RTL each part is a bidi isolate, so a
  /// Latin part ("720p") and a number in the next one ("270 م.ب") don't
  /// merge into one left-to-right run and swap places.
  String joinMeta(Iterable<String> parts) =>
      Directionality.of(this) == TextDirection.rtl
      ? parts.map(isolate).join(' · ')
      : parts.join(' · ');

  /// [text] as a bidi isolate in RTL (first strong character decides).
  String isolate(String text) =>
      Directionality.of(this) == TextDirection.rtl ? '\u2068$text\u2069' : text;

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

/// "14 min left" (at least 1).
String minutesLeft(AppLocalizations l10n, Duration remaining) =>
    l10n.minutesLeft((remaining.inSeconds / 60).ceil().clamp(1, 1 << 20));
