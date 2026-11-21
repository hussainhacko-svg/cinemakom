import 'package:material_ui/material_ui.dart';

import 'marquee_colors.dart';

/// Font families (bundled assets, declared in pubspec.yaml). Each role is a
/// Latin family with an Arabic fallback, so mixed-script titles render
/// correctly without switching styles.
abstract final class MarqueeFonts {
  static const display = 'BigShouldersDisplay';
  static const displayArabic = 'ReemKufi';
  static const ui = 'IBMPlexSans';
  static const uiArabic = 'IBMPlexSansArabic';
}

extension MarqueeWeight on TextStyle {
  /// Sets [weight] as both `fontWeight` (static fonts) and the `wght`
  /// variation (variable fonts). Use this instead of `copyWith(fontWeight:)`.
  TextStyle withWeight(FontWeight weight) => copyWith(
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
  );
}

/// The Marquee type scale (DESIGN.md §2).
///
/// [arabic] drops letter-spacing from tracked styles: Arabic is cursive and
/// tracking breaks the joins. Media titles never carry tracking because they
/// can be in either script.
class MarqueeText {
  const MarqueeText({
    required this.arabic,
    this.palette = MarqueePalette.marquee,
  });

  /// The scale for the UI language and theme palette in effect at [context].
  factory MarqueeText.of(BuildContext context) => MarqueeText(
    arabic: Localizations.localeOf(context).languageCode == 'ar',
    palette: MarqueePalette.of(context),
  );

  final bool arabic;
  final MarqueePalette palette;

  TextStyle get _display => TextStyle(
    fontFamily: MarqueeFonts.display,
    fontFamilyFallback: const [MarqueeFonts.displayArabic],
    color: palette.cream,
  );

  TextStyle get _ui => TextStyle(
    fontFamily: MarqueeFonts.ui,
    fontFamilyFallback: const [MarqueeFonts.uiArabic],
    color: palette.cream,
  );

  double _track(double em, double size) => arabic ? 0 : em * size;

  static final _arabicScript = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  /// True when [text] contains Arabic letters.
  static bool hasArabic(String text) => _arabicScript.hasMatch(text);

  /// Hero titles (UI strings). For media titles use [heroTitleFor].
  TextStyle get heroTitle => _heroTitle(arabicGlyphs: arabic);

  /// Details title (UI strings). For media titles use [displayLargeFor].
  TextStyle get displayLarge => _displayLarge(arabicGlyphs: arabic);

  /// Media titles can be in either script whatever the UI language. Arabic
  /// display glyphs need a roomier line than tight Latin capitals.
  TextStyle heroTitleFor(String title) =>
      _heroTitle(arabicGlyphs: hasArabic(title));

  TextStyle displayLargeFor(String title) =>
      _displayLarge(arabicGlyphs: hasArabic(title));

  TextStyle _heroTitle({required bool arabicGlyphs}) => _display
      .copyWith(fontSize: 58, height: arabicGlyphs ? 1.3 : 0.9)
      .withWeight(FontWeight.w900);

  TextStyle _displayLarge({required bool arabicGlyphs}) => _display
      .copyWith(fontSize: 40, height: arabicGlyphs ? 1.35 : 1.0)
      .withWeight(FontWeight.w800);

  /// Section headers ("CONTINUE WATCHING"). Uppercase in Latin only.
  TextStyle get sectionTitle => _display
      .copyWith(
        fontSize: 22,
        height: arabic ? 1.4 : 1.1,
        letterSpacing: _track(0.04, 22),
      )
      .withWeight(FontWeight.w800);

  /// Episode numbers ("04").
  TextStyle get numeral => _display
      .copyWith(
        fontSize: 34,
        height: 1.0,
        color: palette.bulb,
        fontFeatures: const [FontFeature.tabularFigures()],
      )
      .withWeight(FontWeight.w900);

  TextStyle get title =>
      _ui.copyWith(fontSize: 16, height: 1.3).withWeight(FontWeight.w600);

  TextStyle get body => _ui
      .copyWith(
        fontSize: 15,
        height: arabic ? 1.6 : 1.5,
        color: palette.creamSoft,
      )
      .withWeight(FontWeight.w400);

  /// Buttons.
  TextStyle get label =>
      _ui.copyWith(fontSize: 14, height: 1.2).withWeight(FontWeight.w600);

  /// Metadata ("2023 · Drama · 3h").
  TextStyle get caption => _ui
      .copyWith(fontSize: 12, height: 1.35, color: palette.dust)
      .withWeight(FontWeight.w400);

  /// "NOW SHOWING".
  TextStyle get eyebrow => _ui
      .copyWith(
        fontSize: 12,
        height: 1.2,
        letterSpacing: _track(0.16, 12),
        color: palette.bulb,
      )
      .withWeight(FontWeight.w600);

  TextStyle get navLabel =>
      _ui.copyWith(fontSize: 11, height: 1.2).withWeight(FontWeight.w500);

  /// The Material text theme, so stock widgets match the scale.
  TextTheme get textTheme => TextTheme(
    displayLarge: heroTitle,
    displayMedium: displayLarge,
    headlineSmall: sectionTitle,
    titleLarge: sectionTitle,
    titleMedium: title,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: body.copyWith(color: palette.cream),
    bodySmall: caption,
    labelLarge: label,
    labelMedium: eyebrow,
    labelSmall: navLabel,
  );
}
