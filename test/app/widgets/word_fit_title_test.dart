import 'dart:io';

import 'package:cinemakom/app/theme/marquee_text.dart';
import 'package:cinemakom/app/widgets/word_fit_title.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The real fonts: the test font draws squares and proves nothing.
Future<void> _loadFonts() async {
  Future<ByteData> bytes(String file) async =>
      ByteData.sublistView(await File('assets/fonts/$file').readAsBytes());
  for (final (family, file) in [
    (MarqueeFonts.display, 'BigShouldersDisplay-Variable.ttf'),
    (MarqueeFonts.displayArabic, 'ReemKufi-Variable.ttf'),
  ]) {
    await (FontLoader(family)..addFont(bytes(file))).load();
  }
}

/// The Details title column on phones: 360 to 412 wide, less the gutters,
/// the 128 poster and the gap.
const _widths = <double>[176, 200, 228];

const _titles = <String>[
  'SEKAI SAIKOU NO ANSATSUSHA, ISEKAI KIZOKU NI TENSEI SURU',
  'TENET',
  'THE LORD OF THE RINGS: THE RINGS OF POWER',
  'SUPERCALIFRAGILISTICEXPIALIDOCIOUS',
  'هجوم العمالقة',
];

void main() {
  setUpAll(_loadFonts);

  for (final width in _widths) {
    for (final title in _titles) {
      testWidgets('no word breaks: "$title" at $width', (tester) async {
        final style = const MarqueeText(arabic: false).displayLargeFor(title);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: width,
                child: WordFitTitle(title, style: style),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText),
        );
        final words = RegExp(r'\S+').allMatches(title);
        final shrunk = paragraph.text.style!.fontSize! < style.fontSize!;
        for (final m in words) {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: m.start, extentOffset: m.end),
          );
          final lines = {for (final b in boxes) b.top.round()};
          // Past the smallest size an absurd word may still wrap.
          if (shrunk &&
              paragraph.text.style!.fontSize! <= style.fontSize! * 0.6 + 0.01) {
            continue;
          }
          expect(lines, hasLength(1), reason: '"${m[0]}" broke at $width');
        }
      });
    }
  }

  testWidgets('a title that fits keeps its size', (tester) async {
    final style = const MarqueeText(arabic: false).displayLargeFor('TENET');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 228,
            child: WordFitTitle('TENET', style: style),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(paragraph.text.style!.fontSize, style.fontSize);
  });
}
