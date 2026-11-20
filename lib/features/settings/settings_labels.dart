import '../../app/l10n/app_localizations.dart';
import '../../core/storage/preferences.dart';

// The settings' value labels, shared by the phone and TV Settings (no
// layout).

String qualityLabel(AppLocalizations l10n, PreferredQuality q) =>
    q == PreferredQuality.p2160
    ? l10n.quality4k(q.height)
    : l10n.qualityHeight(q.height);

String subtitleLabel(AppLocalizations l10n, SubtitlePreference s) =>
    switch (s) {
      SubtitlePreference.arabic => l10n.subtitleArabic,
      SubtitlePreference.english => l10n.subtitleEnglish,
      SubtitlePreference.off => l10n.subtitleOff,
    };

String subtitleSizeLabel(AppLocalizations l10n, SubtitleSize s) => switch (s) {
  SubtitleSize.small => l10n.subtitleSizeSmall,
  SubtitleSize.medium => l10n.subtitleSizeMedium,
  SubtitleSize.large => l10n.subtitleSizeLarge,
};

String rotationLabel(AppLocalizations l10n, ScreenRotation r) => switch (r) {
  ScreenRotation.portrait => l10n.rotationPortrait,
  ScreenRotation.auto => l10n.rotationAuto,
};
