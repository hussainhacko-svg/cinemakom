import 'package:material_ui/material_ui.dart';

/// The Marquee palette (docs/DESIGN.md §1). The app has exactly one theme;
/// widgets use these tokens (or the [ThemeData] built from them), never
/// literal colours.
abstract final class MarqueeColors {
  /// App background.
  static const night = Color(0xFF15100C);

  /// Surfaces: panels, sheets, cards, search field.
  static const booth = Color(0xFF221A14);

  /// Selected or hovered rows, pressed surfaces.
  static const boothRaised = Color(0xFF2C221A);

  /// Bottom bar and navigation rail.
  static const navBar = Color(0xFF1B1510);

  /// Dividers, outlines, progress tracks.
  static const velvet = Color(0xFF3A2C21);

  /// Outlined-button borders, inactive indicators.
  static const velvetStrong = Color(0xFF5A4634);

  /// Primary text and icons.
  static const cream = Color(0xFFF4EAD7);

  /// Long text (synopsis).
  static const creamSoft = Color(0xFFCDBEA5);

  /// Captions, metadata, inactive navigation.
  static const dust = Color(0xFFB9A88E);

  /// Decorative only (unwatched episode numerals, disabled). Not for text
  /// that must be read.
  static const dustDim = Color(0xFF6E5C47);

  /// The one accent: primary actions, active nav, progress, focus, 4K badge.
  static const bulb = Color(0xFFF4B740);

  /// Pressed or hovered accent.
  static const bulbBright = Color(0xFFFFD27A);

  /// Text and icons on [bulb].
  static const onBulb = Color(0xFF1A1208);

  /// Errors only.
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
