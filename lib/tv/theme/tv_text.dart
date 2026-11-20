import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_text.dart';
import '../../app/theme/marquee_theme.dart';

/// The Marquee type scale at TV sizes, for reading from 3 m away
/// (docs/TV.md §6.2). Same fonts, weights and Arabic rules as [MarqueeText];
/// only the sizes (and the tracking that follows them) change.
class MarqueeTvText extends MarqueeText {
  const MarqueeTvText({required super.arabic});

  factory MarqueeTvText.of(BuildContext context) => MarqueeTvText(
    arabic: Localizations.localeOf(context).languageCode == 'ar',
  );

  double _track(double em, double size) => arabic ? 0 : em * size;

  @override
  TextStyle get heroTitle => super.heroTitle.copyWith(fontSize: 52);

  @override
  TextStyle heroTitleFor(String title) =>
      super.heroTitleFor(title).copyWith(fontSize: 52);

  @override
  TextStyle get sectionTitle => super.sectionTitle.copyWith(
    fontSize: 24,
    letterSpacing: _track(0.04, 24),
  );

  @override
  TextStyle get title => super.title.copyWith(fontSize: 18);

  @override
  TextStyle get body => super.body.copyWith(fontSize: 17);

  @override
  TextStyle get label => super.label.copyWith(fontSize: 16);

  @override
  TextStyle get caption => super.caption.copyWith(fontSize: 14);

  @override
  TextStyle get eyebrow =>
      super.eyebrow.copyWith(fontSize: 13, letterSpacing: _track(0.16, 13));

  @override
  TextStyle get navLabel => super.navLabel.copyWith(fontSize: 16);

  /// A panel's title ("SUBTITLES", "EPISODE 6"): the display face at 32.
  TextStyle get panelTitle =>
      displayLarge.copyWith(fontSize: 32, height: arabic ? 1.35 : 1.05);
}

/// The one Marquee theme with the TV's type sizes.
ThemeData buildMarqueeTvTheme({required bool arabic}) => buildMarqueeTheme(
  arabic: arabic,
  text: MarqueeTvText(arabic: arabic),
);
