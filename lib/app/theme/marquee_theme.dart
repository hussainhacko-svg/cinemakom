import 'package:material_ui/material_ui.dart';

import 'marquee_colors.dart';
import 'marquee_text.dart';

/// Builds Cinemakom's dark theme for [palette] (default: [MarqueePalette.marquee]).
/// [arabic] only changes letter-spacing (see [MarqueeText]); colours and shapes
/// are identical in both languages. [text] swaps in another size table of the
/// same type scale (the TV's, docs/TV.md §6.2); it must match [arabic].
ThemeData buildMarqueeTheme({
  required bool arabic,
  MarqueePalette palette = MarqueePalette.marquee,
  MarqueeText? text,
}) {
  text ??= MarqueeText(arabic: arabic, palette: palette);
  final c = palette.night;

  WidgetStateProperty<T> selected<T>(T on, T off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );

  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: palette.bulbFill,
    onPrimary: palette.onBulb,
    primaryContainer: palette.boothRaised,
    onPrimaryContainer: palette.cream,
    secondary: palette.creamSoft,
    onSecondary: c,
    tertiary: palette.bulbBright,
    onTertiary: palette.onBulb,
    error: palette.ember,
    onError: c,
    surface: c,
    onSurface: palette.cream,
    onSurfaceVariant: palette.dust,
    surfaceContainerLowest: c,
    surfaceContainerLow: palette.navBar,
    surfaceContainer: palette.booth,
    surfaceContainerHigh: palette.boothRaised,
    surfaceContainerHighest: palette.velvet,
    outline: palette.velvetStrong,
    outlineVariant: palette.velvet,
    inverseSurface: palette.cream,
    onInverseSurface: c,
    inversePrimary: palette.onBulb,
    shadow: Colors.transparent,
    scrim: const Color(0xCC000000),
    surfaceTint: Colors.transparent,
  );

  const pill = StadiumBorder();
  const panelShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(MarqueeRadius.panel),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [palette],
    scaffoldBackgroundColor: c,
    canvasColor: c,
    textTheme: text.textTheme,
    // Cheaper than the default sparkle effect.
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c,
      foregroundColor: palette.cream,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.sectionTitle,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.navBar,
      height: 72,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      // The active tab sits on a boothRaised pill (DESIGN.md §5).
      indicatorColor: palette.boothRaised,
      indicatorShape: pill,
      iconTheme: selected(
        IconThemeData(color: palette.bulb, size: 22),
        IconThemeData(color: palette.dust, size: 22),
      ),
      labelTextStyle: selected(
        text.navLabel
            .copyWith(color: palette.bulb)
            .withWeight(FontWeight.w600),
        text.navLabel.copyWith(color: palette.dust),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: palette.navBar,
      elevation: 0,
      indicatorColor: palette.boothRaised,
      indicatorShape: pill,
      useIndicator: true,
      selectedIconTheme: IconThemeData(color: palette.bulb, size: 22),
      unselectedIconTheme: IconThemeData(color: palette.dust, size: 22),
      selectedLabelTextStyle: text.navLabel
          .copyWith(color: palette.bulb)
          .withWeight(FontWeight.w600),
      unselectedLabelTextStyle: text.navLabel.copyWith(color: palette.dust),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.bulbFill,
        foregroundColor: palette.onBulb,
        disabledBackgroundColor: palette.velvet,
        disabledForegroundColor: palette.dustDim,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
        shape: pill,
        textStyle: text.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.cream,
        side: BorderSide(color: palette.velvetStrong),
        minimumSize: const Size(64, 44),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
        shape: pill,
        textStyle: text.label.withWeight(FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.bulb,
        minimumSize: const Size(44, 44),
        textStyle: text.label.withWeight(FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.cream,
        minimumSize: const Size(44, 44),
        iconSize: 18,
      ),
    ),
    iconTheme: IconThemeData(color: palette.cream, size: 22),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.bulb,
      linearTrackColor: palette.velvet,
      linearMinHeight: 3,
    ),
    dividerTheme: DividerThemeData(
      color: palette.velvet,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: palette.booth,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(MarqueeRadius.card),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.booth,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: MarqueeRadius.panel),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.booth,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: panelShape,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.boothRaised,
      contentTextStyle: text.body.copyWith(color: palette.cream),
      actionTextColor: palette.bulb,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(MarqueeRadius.card),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.booth,
      selectedColor: palette.bulbFill,
      side: BorderSide(color: palette.velvet),
      labelStyle: text.label.withWeight(FontWeight.w500),
      secondaryLabelStyle: text.label.copyWith(color: palette.onBulb),
      shape: pill,
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.booth,
      hintStyle: text.body.copyWith(color: palette.dust),
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        borderSide: BorderSide(color: palette.velvet),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        borderSide: BorderSide(color: palette.velvet),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        borderSide: BorderSide(color: palette.bulb, width: 1.5),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.bulb,
      selectionColor: palette.bulb.withValues(alpha: 0.35),
      selectionHandleColor: palette.bulb,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(palette.velvetStrong),
      radius: const Radius.circular(4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.boothRaised,
        borderRadius: const BorderRadius.all(MarqueeRadius.thumb),
      ),
      textStyle: text.caption.copyWith(color: palette.cream),
    ),
    focusColor: palette.bulb.withValues(alpha: 0.2),
    hoverColor: palette.cream.withValues(alpha: 0.08),
    highlightColor: Colors.transparent,
  );
}
