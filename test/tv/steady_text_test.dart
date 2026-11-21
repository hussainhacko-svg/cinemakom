import 'dart:io';

import 'package:cinemakom/app/theme/marquee_text.dart';
import 'package:cinemakom/tv/theme/tv_text.dart';
import 'package:cinemakom/tv/widgets/tv_steady_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The real UI font: the test font draws every weight the same width, so
/// it would hide the bug.
Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(
    await File('assets/fonts/IBMPlexSans-Variable.ttf').readAsBytes(),
  );
  await (FontLoader(MarqueeFonts.ui)..addFont(Future.value(bytes))).load();
}

void main() {
  setUpAll(_loadFonts);

  Future<double> width(WidgetTester tester, Widget label) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: UnconstrainedBox(child: label)),
      ),
    );
    return tester.getSize(find.byWidget(label)).width;
  }

  testWidgets('focus (weight 600) never changes a label\'s width', (
    tester,
  ) async {
    final style = const MarqueeTvText(arabic: false).label;
    for (final label in ['Download', 'Favorite', 'Trailer', '1080p']) {
      final plain500 = await width(
        tester,
        Text(label, style: style.withWeight(FontWeight.w500)),
      );
      final plain600 = await width(
        tester,
        Text(label, style: style.withWeight(FontWeight.w600)),
      );
      // The bug: a plain label grows when it turns bold.
      expect(plain600, greaterThan(plain500), reason: label);

      final steady500 = await width(
        tester,
        TvSteadyText(label, style: style.withWeight(FontWeight.w500)),
      );
      final steady600 = await width(
        tester,
        TvSteadyText(label, style: style.withWeight(FontWeight.w600)),
      );
      expect(steady500, steady600, reason: label);
    }
  });
}
