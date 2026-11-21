import 'package:material_ui/material_ui.dart';

import '../../core/storage/preferences.dart' show AppThemeProfile;

/// A complete dark cinema colour palette (docs/DESIGN.md §1).
///
/// Widgets read the active palette via `context.palette` (or
/// `MarqueePalette.of(context)`) so switching between [marquee] and [bordeaux]
/// updates every screen live across mobile, desktop, Android TV, and Apple TV.
@immutable
class MarqueePalette extends ThemeExtension<MarqueePalette> {
  const MarqueePalette({
    required this.night,
    required this.screen,
    required this.booth,
    required this.boothRaised,
    required this.navBar,
    required this.velvet,
    required this.velvetStrong,
    required this.cream,
    required this.creamSoft,
    required this.dust,
    required this.dustDim,
    required this.bulb,
    required this.bulbFill,
    required this.bulbBright,
    required this.onBulb,
    required this.ember,
  });

  /// App background.
  final Color night;

  /// Player backdrop behind the video (true black for OLED letterbox bars).
  final Color screen;

  /// Surfaces: panels, sheets, cards, search field.
  final Color booth;

  /// Selected or hovered rows, pressed surfaces, active nav pill.
  final Color boothRaised;

  /// Bottom bar and navigation rail.
  final Color navBar;

  /// Dividers, outlines, progress tracks.
  final Color velvet;

  /// Outlined-button borders, inactive indicators.
  final Color velvetStrong;

  /// Primary text and icons.
  final Color cream;

  /// Long text (synopsis).
  final Color creamSoft;

  /// Captions, metadata, inactive navigation.
  final Color dust;

  /// Decorative only (unwatched episode numerals, disabled).
  final Color dustDim;

  /// Luminous accent for text, icons, active nav, progress, focus rings.
  final Color bulb;

  /// Filled primary CTA buttons and 4K badges.
  final Color bulbFill;

  /// Pressed or hovered primary CTA fill.
  final Color bulbBright;

  /// Text and icons on [bulbFill].
  final Color onBulb;

  /// Errors only.
  final Color ember;

  /// Original Marquee palette: deep cocoa & warm bulb gold (default).
  static const marquee = MarqueePalette(
    night: Color(0xFF15100C),
    screen: Color(0xFF000000),
    booth: Color(0xFF221A14),
    boothRaised: Color(0xFF2C221A),
    navBar: Color(0xFF1B1510),
    velvet: Color(0xFF3A2C21),
    velvetStrong: Color(0xFF5A4634),
    cream: Color(0xFFF4EAD7),
    creamSoft: Color(0xFFCDBEA5),
    dust: Color(0xFFB9A88E),
    dustDim: Color(0xFF6E5C47),
    bulb: Color(0xFFF4B740),
    bulbFill: Color(0xFFF4B740),
    bulbBright: Color(0xFFFFD27A),
    onBulb: Color(0xFF1A1208),
    ember: Color(0xFFE8735A),
  );

  /// Bordeaux Curtain palette: obsidian black, deep Bordeaux wine CTAs,
  /// luminous ruby indicators, warm alabaster ivory text.
  static const bordeaux = MarqueePalette(
    night: Color(0xFF0B0809),
    screen: Color(0xFF000000),
    booth: Color(0xFF181014),
    boothRaised: Color(0xFF24161C),
    navBar: Color(0xFF110C0E),
    velvet: Color(0xFF3D1F2B),
    velvetStrong: Color(0xFF633245),
    cream: Color(0xFFF6ECEE),
    creamSoft: Color(0xFFD4C2C6),
    dust: Color(0xFFB8A2A8),
    dustDim: Color(0xFF6A5058),
    bulb: Color(0xFFEA5A73),
    bulbFill: Color(0xFF9B1B30),
    bulbBright: Color(0xFFB8223B),
    onBulb: Color(0xFFFFF6F7),
    ember: Color(0xFFF2915E),
  );

  static MarqueePalette forProfile(AppThemeProfile profile) => switch (profile) {
    AppThemeProfile.marquee => marquee,
    AppThemeProfile.bordeaux => bordeaux,
  };

  /// The active palette from the enclosing [Theme], falling back to [marquee].
  static MarqueePalette of(BuildContext context) =>
      Theme.of(context).extension<MarqueePalette>() ?? marquee;

  @override
  MarqueePalette copyWith({
    Color? night,
    Color? screen,
    Color? booth,
    Color? boothRaised,
    Color? navBar,
    Color? velvet,
    Color? velvetStrong,
    Color? cream,
    Color? creamSoft,
    Color? dust,
    Color? dustDim,
    Color? bulb,
    Color? bulbFill,
    Color? bulbBright,
    Color? onBulb,
    Color? ember,
  }) => MarqueePalette(
    night: night ?? this.night,
    screen: screen ?? this.screen,
    booth: booth ?? this.booth,
    boothRaised: boothRaised ?? this.boothRaised,
    navBar: navBar ?? this.navBar,
    velvet: velvet ?? this.velvet,
    velvetStrong: velvetStrong ?? this.velvetStrong,
    cream: cream ?? this.cream,
    creamSoft: creamSoft ?? this.creamSoft,
    dust: dust ?? this.dust,
    dustDim: dustDim ?? this.dustDim,
    bulb: bulb ?? this.bulb,
    bulbFill: bulbFill ?? this.bulbFill,
    bulbBright: bulbBright ?? this.bulbBright,
    onBulb: onBulb ?? this.onBulb,
    ember: ember ?? this.ember,
  );

  @override
  MarqueePalette lerp(ThemeExtension<MarqueePalette>? other, double t) {
    if (other is! MarqueePalette) return this;
    return MarqueePalette(
      night: Color.lerp(night, other.night, t)!,
      screen: Color.lerp(screen, other.screen, t)!,
      booth: Color.lerp(booth, other.booth, t)!,
      boothRaised: Color.lerp(boothRaised, other.boothRaised, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      velvet: Color.lerp(velvet, other.velvet, t)!,
      velvetStrong: Color.lerp(velvetStrong, other.velvetStrong, t)!,
      cream: Color.lerp(cream, other.cream, t)!,
      creamSoft: Color.lerp(creamSoft, other.creamSoft, t)!,
      dust: Color.lerp(dust, other.dust, t)!,
      dustDim: Color.lerp(dustDim, other.dustDim, t)!,
      bulb: Color.lerp(bulb, other.bulb, t)!,
      bulbFill: Color.lerp(bulbFill, other.bulbFill, t)!,
      bulbBright: Color.lerp(bulbBright, other.bulbBright, t)!,
      onBulb: Color.lerp(onBulb, other.onBulb, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
    );
  }
}

/// Shorthand for reading the active [MarqueePalette] inside any widget build.
extension MarqueePaletteContext on BuildContext {
  MarqueePalette get palette => MarqueePalette.of(this);
}

/// Default Marquee palette constants (kept for tests & static references).
/// Widgets should use `context.palette` so theme changes apply live.
abstract final class MarqueeColors {
  static const night = Color(0xFF15100C);
  static const screen = Color(0xFF000000);
  static const booth = Color(0xFF221A14);
  static const boothRaised = Color(0xFF2C221A);
  static const navBar = Color(0xFF1B1510);
  static const velvet = Color(0xFF3A2C21);
  static const velvetStrong = Color(0xFF5A4634);
  static const cream = Color(0xFFF4EAD7);
  static const creamSoft = Color(0xFFCDBEA5);
  static const dust = Color(0xFFB9A88E);
  static const dustDim = Color(0xFF6E5C47);
  static const bulb = Color(0xFFF4B740);
  static const bulbFill = Color(0xFFF4B740);
  static const bulbBright = Color(0xFFFFD27A);
  static const onBulb = Color(0xFF1A1208);
  static const ember = Color(0xFFE8735A);
}

/// Spacing scale (multiples of 4) and screen gutters (DESIGN.md §3).
abstract final class MarqueeSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Horizontal screen padding for a given window width.
  static double gutter(double width) => width >= 1200
      ? 48
      : width >= 600
      ? 32
      : 20;
}

/// Corner radii (DESIGN.md §3).
abstract final class MarqueeRadius {
  static const thumb = Radius.circular(6);
  static const poster = Radius.circular(10);
  static const card = Radius.circular(12);
  static const panel = Radius.circular(16);
}
