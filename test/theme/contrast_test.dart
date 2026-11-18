import 'dart:io';

import 'package:cinemakom/app/theme/marquee_colors.dart';
import 'package:cinemakom/app/theme/marquee_text.dart';
import 'package:cinemakom/app/theme/marquee_theme.dart';
import 'package:cinemakom/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const surfaces = {
    'night': MarqueeColors.night,
    'booth': MarqueeColors.booth,
    'boothRaised': MarqueeColors.boothRaised,
    'navBar': MarqueeColors.navBar,
  };
  const texts = {
    'cream': MarqueeColors.cream,
    'creamSoft': MarqueeColors.creamSoft,
    'dust': MarqueeColors.dust,
    'bulb': MarqueeColors.bulb,
    'ember': MarqueeColors.ember,
  };

  for (final s in surfaces.entries) {
    for (final t in texts.entries) {
      test('${t.key} on ${s.key} is readable (>= 4.5:1)', () {
        expect(contrast(t.value, s.value), greaterThanOrEqualTo(4.5));
      });
    }
  }

  test('onBulb on bulb is readable', () {
    expect(
      contrast(MarqueeColors.onBulb, MarqueeColors.bulb),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('one dark theme; Arabic only drops letter-spacing', () {
    final en = buildMarqueeTheme(arabic: false);
    final ar = buildMarqueeTheme(arabic: true);
    expect(en.colorScheme, ar.colorScheme);
    expect(en.brightness, Brightness.dark);
    expect(
      const MarqueeText(arabic: false).sectionTitle.letterSpacing,
      greaterThan(0),
    );
    expect(const MarqueeText(arabic: true).sectionTitle.letterSpacing, 0);
    expect(const MarqueeText(arabic: true).eyebrow.letterSpacing, 0);
    expect(const MarqueeText(arabic: false).heroTitle.letterSpacing, isNull);
  });

  test('every text style falls back to the Arabic family', () {
    final theme = buildMarqueeTheme(arabic: false).textTheme;
    for (final style in [
      theme.displayLarge,
      theme.titleLarge,
      theme.bodyMedium,
      theme.labelLarge,
    ]) {
      expect(style!.fontFamilyFallback, isNotEmpty);
    }
  });

  test('variable fonts get the weight as a wght variation', () {
    const t = MarqueeText(arabic: false);
    for (final style in [
      t.heroTitle,
      t.sectionTitle,
      t.title,
      t.body,
      t.label,
      t.caption,
      t.navLabel,
    ]) {
      expect(style.fontVariations, [
        FontVariation.weight(style.fontWeight!.value.toDouble()),
      ]);
    }
  });

  test('display styles give Arabic titles a roomier line', () {
    const en = MarqueeText(arabic: false);
    expect(MarqueeText.hasArabic('صراع العروش'), isTrue);
    expect(MarqueeText.hasArabic('Tenet'), isFalse);
    expect(en.heroTitleFor('TENET').height, lessThan(1));
    expect(en.heroTitleFor('ايزيل').height, greaterThan(1.2));
    expect(en.displayLargeFor('ايزيل').height, greaterThan(1.2));
    expect(
      const MarqueeText(arabic: true).sectionTitle.height,
      greaterThan(1.3),
    );
  });

  test('every declared font file exists', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'asset: (assets/fonts/\S+)')
        .allMatches(pubspec)
        .map((m) => m[1]!)
        .toList();
    expect(assets, hasLength(6));
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
  });

  test('every bundled font has its OFL license next to it', () {
    for (final file in fontLicenses.values) {
      final text = File('assets/fonts/licenses/$file').readAsStringSync();
      expect(text, contains('SIL Open Font License'), reason: file);
    }
  });

  testWidgets('font licenses are registered for the licenses page', (
    tester,
  ) async {
    registerFontLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(packages, containsAll(fontLicenses.keys));
  });
}
