import 'package:material_ui/material_ui.dart';

import 'marquee_colors.dart';
import 'marquee_text.dart';

/// The app's single theme (DESIGN.md). [arabic] only changes letter-spacing
/// (see [MarqueeText]); colours and shapes are identical in both languages.
/// [text] swaps in another size table of the same type scale (the TV's,
/// docs/TV.md §6.2); it must match [arabic].
ThemeData buildMarqueeTheme({required bool arabic, MarqueeText? text}) {
  text ??= MarqueeText(arabic: arabic);
  const c = MarqueeColors.night;

  WidgetStateProperty<T> selected<T>(T on, T off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );

  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: MarqueeColors.bulb,
    onPrimary: MarqueeColors.onBulb,
    primaryContainer: MarqueeColors.boothRaised,
    onPrimaryContainer: MarqueeColors.cream,
    secondary: MarqueeColors.creamSoft,
    onSecondary: c,
    tertiary: MarqueeColors.bulbBright,
    onTertiary: MarqueeColors.onBulb,
    error: MarqueeColors.ember,
    onError: c,
    surface: c,
    onSurface: MarqueeColors.cream,
    onSurfaceVariant: MarqueeColors.dust,
    surfaceContainerLowest: c,
    surfaceContainerLow: MarqueeColors.navBar,
    surfaceContainer: MarqueeColors.booth,
    surfaceContainerHigh: MarqueeColors.boothRaised,
    surfaceContainerHighest: MarqueeColors.velvet,
    outline: MarqueeColors.velvetStrong,
    outlineVariant: MarqueeColors.velvet,
    inverseSurface: MarqueeColors.cream,
    onInverseSurface: c,
    inversePrimary: MarqueeColors.onBulb,
    shadow: Colors.transparent,
    scrim: Color(0xCC000000),
    surfaceTint: Colors.transparent,
  );

  const pill = StadiumBorder();
  const panelShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(MarqueeRadius.panel),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c,
    canvasColor: c,
    textTheme: text.textTheme,
    // Cheaper than the default sparkle effect.
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c,
      foregroundColor: MarqueeColors.cream,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.sectionTitle,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MarqueeColors.navBar,
      height: 72,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      // The active tab sits on a boothRaised pill (DESIGN.md §5).
      indicatorColor: MarqueeColors.boothRaised,
      indicatorShape: pill,
      iconTheme: selected(
        const IconThemeData(color: MarqueeColors.bulb, size: 22),
        const IconThemeData(color: MarqueeColors.dust, size: 22),
      ),
      labelTextStyle: selected(
        text.navLabel
            .copyWith(color: MarqueeColors.bulb)
            .withWeight(FontWeight.w600),
        text.navLabel.copyWith(color: MarqueeColors.dust),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: MarqueeColors.navBar,
      elevation: 0,
      indicatorColor: MarqueeColors.boothRaised,
      indicatorShape: pill,
      useIndicator: true,
      selectedIconTheme: const IconThemeData(
        color: MarqueeColors.bulb,
        size: 22,
      ),
      unselectedIconTheme: const IconThemeData(
        color: MarqueeColors.dust,
        size: 22,
      ),
      selectedLabelTextStyle: text.navLabel
          .copyWith(color: MarqueeColors.bulb)
          .withWeight(FontWeight.w600),
      unselectedLabelTextStyle: text.navLabel.copyWith(
        color: MarqueeColors.dust,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarqueeColors.bulb,
        foregroundColor: MarqueeColors.onBulb,
        disabledBackgroundColor: MarqueeColors.velvet,
        disabledForegroundColor: MarqueeColors.dustDim,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
        shape: pill,
        textStyle: text.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MarqueeColors.cream,
        side: const BorderSide(color: MarqueeColors.velvetStrong),
        minimumSize: const Size(64, 44),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
        shape: pill,
        textStyle: text.label.withWeight(FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MarqueeColors.bulb,
        minimumSize: const Size(44, 44),
        textStyle: text.label.withWeight(FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: MarqueeColors.cream,
        minimumSize: const Size(44, 44),
        iconSize: 18,
      ),
    ),
    iconTheme: const IconThemeData(color: MarqueeColors.cream, size: 22),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MarqueeColors.bulb,
      linearTrackColor: MarqueeColors.velvet,
      linearMinHeight: 3,
    ),
    dividerTheme: const DividerThemeData(
      color: MarqueeColors.velvet,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      color: MarqueeColors.booth,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(MarqueeRadius.card),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MarqueeColors.booth,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: MarqueeRadius.panel),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MarqueeColors.booth,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: panelShape,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MarqueeColors.boothRaised,
      contentTextStyle: text.body.copyWith(color: MarqueeColors.cream),
      actionTextColor: MarqueeColors.bulb,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(MarqueeRadius.card),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MarqueeColors.booth,
      selectedColor: MarqueeColors.bulb,
      side: const BorderSide(color: MarqueeColors.velvet),
      labelStyle: text.label.withWeight(FontWeight.w500),
      secondaryLabelStyle: text.label.copyWith(color: MarqueeColors.onBulb),
      shape: pill,
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarqueeColors.booth,
      hintStyle: text.body.copyWith(color: MarqueeColors.dust),
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        borderSide: BorderSide(color: MarqueeColors.velvet),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        borderSide: BorderSide(color: MarqueeColors.velvet),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        borderSide: BorderSide(color: MarqueeColors.bulb, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MarqueeColors.bulb,
      selectionColor: Color(0x59F4B740),
      selectionHandleColor: MarqueeColors.bulb,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(MarqueeColors.velvetStrong),
      radius: const Radius.circular(4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: MarqueeColors.boothRaised,
        borderRadius: BorderRadius.all(MarqueeRadius.thumb),
      ),
      textStyle: text.caption.copyWith(color: MarqueeColors.cream),
    ),
    focusColor: const Color(0x33F4B740),
    hoverColor: const Color(0x14F4EAD7),
    highlightColor: Colors.transparent,
  );
}
