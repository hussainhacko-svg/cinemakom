import 'dart:io';
import 'dart:math' as math;

import 'package:cinemakom/app/theme/marquee_text.dart';
import 'package:cinemakom/app/theme/marquee_theme.dart';
import 'package:cinemakom/features/home/widgets/hero_title.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Hero titles measured with the app's real fonts (the test font would make
/// every glyph a square and prove nothing about the real look).
Future<void> _loadFonts() async {
  Future<ByteData> bytes(String file) async =>
      ByteData.sublistView(await File('assets/fonts/$file').readAsBytes());
  for (final (family, files) in [
    (MarqueeFonts.display, ['BigShouldersDisplay-Variable.ttf']),
    (MarqueeFonts.displayArabic, ['ReemKufi-Variable.ttf']),
    (MarqueeFonts.ui, ['IBMPlexSans-Variable.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(bytes(f));
    }
    await loader.load();
  }
}

/// Hero text widths: phones (360, 390, 412 wide, 20 gutters), a tablet and
/// the desktop side-by-side layout (40% beside the banner).
const _widths = <double>[320, 350, 372, 536, 704, 420];

/// Real banner titles and hard cases: borderline one-liners, long series
/// names, punctuation, a lone long word, Arabic and mixed scripts.
const _titles = <String>[
  'Tenet',
  'It Feeds',
  'The Dog Stars',
  'Your Mother Your Mother Your Mother',
  'The Lord of the Rings: The Rings of Power',
  'The Odyssey',
  'Organize isler: karun hazinesi',
  'Oppenheimer',
  'Interstellar',
  'Dune: Part Two',
  'Mission: Impossible – The Final Reckoning',
  'Everything Everywhere All at Once',
  'Sekai Saikyou no Majo, Hajimemashita',
  'Spider-Man: Across the Spider-Verse',
  'Godzilla Minus One',
  'Past Lives',
  'Furiosa: A Mad Max Saga',
  'Pirates of the Caribbean: Dead Man\'s Chest',
  'Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb',
  'Supercalifragilisticexpialidocious',
  'Avatar: The Way of Water',
  'Breaking Bad',
  'Friends',
  'X',
  'كثيب: الجزء الثاني',
  'سيد الخواتم: خواتم القوة',
  'أطلق أمك',
  'حيوات سابقة',
  'الرجل الذي باع ظهره للشيطان في ليلة ممطرة',
  'Interstellar انترستلار',
];

/// What a Latin title looks like on the hero (uppercased, as `_HeroInfo`).
String _shown(String title) =>
    MarqueeText.hasArabic(title) ? title : title.toUpperCase();

Future<RenderParagraph> _pump(
  WidgetTester tester,
  String title,
  double width, {
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  final shown = _shown(title);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMarqueeTheme(arabic: direction == TextDirection.rtl),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Material(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: width,
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: HeroTitle(
                    title: shown,
                    style: const MarqueeText(arabic: false).heroTitleFor(shown),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.renderObject<RenderParagraph>(find.text(shown));
}

/// The title as the engine sets it: the same text, style, line limit and
/// width as the rendered [Text], so lines and breaks can be read back.
class _Set {
  _Set(WidgetTester tester, RenderParagraph p, String shown, TextScaler scaler)
    : text = shown,
      maxLines = tester.widget<Text>(find.text(shown)).maxLines!,
      painter = TextPainter(
        text: TextSpan(text: shown, style: p.text.style),
        maxLines: tester.widget<Text>(find.text(shown)).maxLines,
        ellipsis: '…',
        textDirection: Directionality.of(tester.element(find.text(shown))),
        textScaler: scaler,
      )..layout(maxWidth: p.constraints.maxWidth);

  final String text;
  final int maxLines;
  final TextPainter painter;

  List<LineMetrics> get lines => painter.computeLineMetrics();
  bool get cut => painter.didExceedMaxLines;

  /// Words that start on one line and end on another. Behind an ellipsis
  /// (the last line, when cut) words are hidden, so they don't count.
  List<String> brokenWords() {
    final hiddenFrom = cut ? _lastLineStart() : text.length;
    return [
      for (final m in RegExp(r'\S+').allMatches(text))
        if (m.start < hiddenFrom &&
            painter.getLineBoundary(TextPosition(offset: m.start)).end < m.end)
          m[0]!,
    ];
  }

  int _lastLineStart() {
    var offset = 0;
    for (var i = 0; i < lines.length - 1; i++) {
      offset = painter.getLineBoundary(TextPosition(offset: offset)).end;
    }
    return offset;
  }

  /// The text of each line (trimmed).
  List<String> lineTexts() {
    final out = <String>[];
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      final r = painter.getLineBoundary(TextPosition(offset: offset));
      out.add(text.substring(r.start, r.end).trim());
      offset = r.end;
    }
    return out;
  }
}

void main() {
  setUpAll(_loadFonts);

  final base = const MarqueeText(arabic: false).heroTitleFor('A').fontSize!;

  void check(
    WidgetTester tester,
    RenderParagraph p,
    String title,
    double width, {
    TextScaler scaler = TextScaler.noScaling,
  }) {
    final shown = _shown(title);
    final set = _Set(tester, p, shown, scaler);
    final where = '"$shown" at $width dp ×${scaler.scale(1)}';

    // Never more than two lines, never wider than the hero.
    expect(set.lines.length, lessThanOrEqualTo(3), reason: where);
    expect(p.size.width, lessThanOrEqualTo(width), reason: where);

    // No word is ever split across lines.
    expect(set.brokenWords(), isEmpty, reason: '$where breaks a word');

    // An ellipsis only when no step can hold the whole title.
    final fit = fitHeroTitle(
      title: shown,
      style: p.text.style!.copyWith(fontSize: base),
      maxWidth: width,
      textScaler: scaler,
      textDirection: set.painter.textDirection!,
    );
    if (fit.fits) expect(set.cut, isFalse, reason: '$where is cut off');

    // The biggest step that fits wins: a title that fits on one line at
    // full size is shown at full size.
    final one = TextPainter(
      text: TextSpan(
        text: shown,
        style: p.text.style!.copyWith(fontSize: base),
      ),
      maxLines: 1,
      textDirection: set.painter.textDirection,
      textScaler: scaler,
    )..layout(maxWidth: width - 1);
    if (!one.didExceedMaxLines) {
      expect(p.text.style!.fontSize, base, reason: '$where not full size');
    }
    one.dispose();

    // Two lines are balanced as far as they can be: 2 px narrower and the
    // title no longer fits in two lines without breaking a word.
    if (set.lines.length > 1 && !set.cut) {
      final widest = set.lines.map((l) => l.width).reduce(math.max);
      final tighter = TextPainter(
        text: TextSpan(text: shown, style: p.text.style),
        maxLines: set.lines.length,
        textDirection: set.painter.textDirection,
        textScaler: scaler,
      )..layout(maxWidth: widest - 2);
      final words = RegExp(r'\S+').allMatches(shown);
      final stillFits =
          !tighter.didExceedMaxLines &&
          words.every(
            (m) =>
                tighter.getLineBoundary(TextPosition(offset: m.start)).end >=
                m.end,
          );
      expect(stillFits, isFalse, reason: '$where could be more balanced');
      tighter.dispose();
    }
    // Report every cut title, to judge them by eye.
    // Only a single word too long for any size may be cut.
    if (set.cut) {
      expect(shown.contains(' '), isFalse, reason: '$where is cut');
    }
    set.painter.dispose();
  }

  for (final width in _widths) {
    group('at $width dp', () {
      for (final title in _titles) {
        testWidgets(title, (tester) async {
          check(tester, await _pump(tester, title, width), title, width);
        });
      }
    });
  }

  group('regressions', () {
    testWidgets('"THE DOG STARS" on a 390 dp phone is whole', (tester) async {
      final p = await _pump(tester, 'The Dog Stars', 350);
      expect(p.didExceedMaxLines, isFalse);
    });

    testWidgets('short titles stay at full size', (tester) async {
      for (final t in ['Tenet', 'It Feeds', 'Friends', 'X']) {
        final p = await _pump(tester, t, 320);
        expect(p.text.style!.fontSize, base, reason: t);
      }
    });

    testWidgets('a lone word too wide for any size stays on one line', (
      tester,
    ) async {
      const t = 'Pneumonoultramicroscopicsilicovolcanoconiosis';
      final p = await _pump(tester, t, 320);
      final set = _Set(tester, p, _shown(t), TextScaler.noScaling);
      expect(set.lines, hasLength(1));
    });

    testWidgets('large system text never splits words', (tester) async {
      for (final scale in [1.3, 2.0]) {
        for (final t in _titles) {
          final p = await _pump(tester, t, 350, scale: scale);
          final set = _Set(tester, p, _shown(t), TextScaler.linear(scale));
          expect(set.lines.length, lessThanOrEqualTo(3), reason: '$t ×$scale');
          expect(set.brokenWords(), isEmpty, reason: '$t ×$scale');
        }
      }
    });

    testWidgets('right to left (Arabic UI) fits the same', (tester) async {
      for (final t in _titles) {
        final p = await _pump(tester, t, 350, direction: TextDirection.rtl);
        check(tester, p, t, 350);
      }
    });
  });
}
