import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('app starts in English with LTR layout', (tester) async {
    await tester.pumpWidget(const CinemakomApp());
    await tester.pumpAndSettle();

    expect(find.text('Cinemakom'), findsWidgets);
    final direction = Directionality.of(tester.element(find.byType(Scaffold)));
    expect(direction, TextDirection.ltr);
  });

  test('Arabic and English are both supported', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode),
      containsAll(['en', 'ar']),
    );
  });
}
