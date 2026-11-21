import 'package:material_ui/material_ui.dart';

/// Space on the TV canvas: 960 × 540 dp, the size Android TV draws apps at
/// (docs/TV.md §6.1; the TCL measures 960 × 540 at ratio 2).
abstract final class TvSpace {
  /// Overscan safe area: 5% of the screen. Nothing focusable goes outside.
  static const double safeH = 48;
  static const double safeV = 27;

  /// Where the page scrolls a focused zone's top to (R10).
  static const double pageKeyline = safeV;

  /// Where Home scrolls a row's top, its title (owner's call, 2026-11-21:
  /// 27 put the title too low). The cards under it stay in the safe area.
  static const double homeRowKeyline = 16;

  /// The gap kept between a focused item and a scroll edge when the page
  /// or a column only scrolls as far as needed.
  static const double revealMargin = safeV;

  /// Focusable things are at least this tall (§6.2).
  static const double minTarget = 48;

  static const EdgeInsetsDirectional safe = EdgeInsetsDirectional.symmetric(
    horizontal: safeH,
    vertical: safeV,
  );
}

/// The focus look (docs/TV.md §6.3).
abstract final class TvFocusStyle {
  /// A focused card grows to this size, around its centre.
  static const double cardScale = 1.08;

  /// Wide cards (Continue watching, 300 wide) grow less: 8% would push them
  /// 12 px out on each side, under the next card. 4% is about a poster's
  /// growth in pixels.
  static const double wideCardScale = 1.04;

  /// The `bulb` ring around anything focused.
  static const double ring = 3;

  /// How far out from its edge the ring sits: a card's, a button's or
  /// chip's, a row's (it touches the row).
  static const double cardGap = 3;
  static const double buttonGap = 2;

  /// How far a button's ring reaches past its edge: room to leave above a
  /// button at the top of a scroll view, which clips there.
  static const double buttonOutset = buttonGap + ring;

  /// The grow, and scrolling that follows focus.
  static const Duration duration = Duration(milliseconds: 150);
  static const Curve curve = Curves.easeOut;
}
