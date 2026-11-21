import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import 'player_state.dart';
import 'subtitles.dart';

// The player's labels, shared by the phone and TV players (no layout).

/// "18:42", or "1:05:09" from an hour up. Western digits in every locale
/// (DESIGN.md §2).
String formatClock(Duration d) {
  final negative = d.isNegative;
  final t = d.abs();
  final h = t.inHours;
  final m = t.inMinutes.remainder(60);
  final s = t.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  final text = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return negative ? '−$text' : text;
}

/// "+1.5", "0", "−0.5" (Western digits, DESIGN.md §2).
String delayLabel(Duration delay) {
  final ms = delay.inMilliseconds;
  if (ms == 0) return '0';
  final abs = ms.abs() / 1000;
  final digits = abs == abs.roundToDouble()
      ? abs.toStringAsFixed(0)
      : abs.toStringAsFixed(ms % 100 == 0 ? 1 : 2);
  return '${ms > 0 ? '+' : '−'}$digits';
}

IconData fitIcon(VideoFit fit) => switch (fit) {
  VideoFit.fit => Icons.fit_screen_outlined,
  VideoFit.fill => Icons.crop_free,
  VideoFit.stretch => Icons.aspect_ratio,
};

/// "Fit", "Fill", "Stretch".
String fitLabel(AppLocalizations l10n, VideoFit fit) => switch (fit) {
  VideoFit.fit => l10n.playerFit,
  VideoFit.fill => l10n.playerFill,
  VideoFit.stretch => l10n.playerStretch,
};

/// "1×", "1.25×". Wrapped in a left-to-right isolate, or Arabic text
/// shows "×1".
String speedLabel(double speed) {
  final s = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '\u2066$s×\u2069';
}

/// The subtitle menu and chip label for [option].
String subtitleLabel(AppLocalizations l10n, SubtitleOption option) {
  if (option.isOff) return l10n.subtitleOff;
  if (option.isStyled) return l10n.subtitleStyledArabic;
  return switch (option.languageCode) {
    'ar' => l10n.subtitleArabic,
    'en' => l10n.subtitleEnglish,
    final code => code?.toUpperCase() ?? l10n.subtitleOff,
  };
}

/// How long the player's controls take to fade in and out, on every
/// platform: TV, phones and desktop (owner, 2026-11-22).
const controlsFade = Duration(milliseconds: 200);
