import 'package:cinemakom/app/theme/marquee_colors.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/features/settings/settings_screen.dart';
import 'package:cinemakom/tv/screens/settings/tv_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_harness.dart';
import '../tv/tv_driver.dart';

void main() {
  test('theme preference defaults to Marquee and parses Bordeaux', () {
    expect(const AppSettings().theme, AppThemeProfile.marquee);
    expect(
      readSettings(MemoryPreferenceStore()).theme,
      AppThemeProfile.marquee,
    );
    expect(
      readSettings(
        MemoryPreferenceStore({PreferenceKeys.theme: 'unknown'}),
      ).theme,
      AppThemeProfile.marquee,
    );
    expect(
      readSettings(
        MemoryPreferenceStore({PreferenceKeys.theme: 'bordeaux'}),
      ).theme,
      AppThemeProfile.bordeaux,
    );
  });

  testWidgets('Phone Settings switches live from Marquee to Bordeaux', (
    tester,
  ) async {
    final store = MemoryPreferenceStore({PreferenceKeys.language: 'en'});
    await pumpApp(tester, store: store);

    // Navigate to Settings tab.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final settingsContext = tester.element(find.byType(SettingsScreen));
    expect(MarqueePalette.of(settingsContext), MarqueePalette.marquee);
    expect(
      Theme.of(settingsContext).scaffoldBackgroundColor,
      MarqueePalette.marquee.night,
    );

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Marquee (Gold)'), findsOneWidget);

    // Open picker and choose Bordeaux (Red).
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bordeaux (Red)'));
    await tester.pumpAndSettle();

    final updatedContext = tester.element(find.byType(SettingsScreen));
    expect(MarqueePalette.of(updatedContext), MarqueePalette.bordeaux);
    expect(
      Theme.of(updatedContext).scaffoldBackgroundColor,
      MarqueePalette.bordeaux.night,
    );
    expect(find.text('Bordeaux (Red)'), findsOneWidget);
    expect(store.getString(PreferenceKeys.theme), 'bordeaux');
  });

  testWidgets('TV Settings switches live to Bordeaux and keeps focus on Theme', (
    tester,
  ) async {
    final store = MemoryPreferenceStore({PreferenceKeys.language: 'en'});
    await pumpApp(tester, tv: true, store: store);
    final tv = TvDriver(tester);

    // Move to tab bar and open Settings.
    await tv.back();
    await tv.focusLabel('Settings');
    await tv.ok();
    expect(find.byType(TvSettingsScreen), findsOneWidget);

    final initialCtx = tester.element(find.byType(TvSettingsScreen));
    expect(MarqueePalette.of(initialCtx), MarqueePalette.marquee);

    // Move down into Settings list: index 0 = Language, index 1 = Theme.
    await tv.down();
    await tv.down();
    expect(tv.focused, contains('Theme'));

    // Open Theme panel, pick Bordeaux (Red), confirm.
    await tv.ok();
    await tv.down();
    await tv.ok();

    final updatedCtx = tester.element(find.byType(TvSettingsScreen));
    expect(MarqueePalette.of(updatedCtx), MarqueePalette.bordeaux);
    expect(
      Theme.of(updatedCtx).scaffoldBackgroundColor,
      MarqueePalette.bordeaux.night,
    );
    expect(store.getString(PreferenceKeys.theme), 'bordeaux');
    expect(tv.focused, contains('Theme'));
  });

  testWidgets('Arabic Settings renders Bordeaux theme label and palette', (
    tester,
  ) async {
    final store = MemoryPreferenceStore({
      PreferenceKeys.language: 'ar',
      PreferenceKeys.theme: 'bordeaux',
    });
    await pumpApp(tester, store: store);

    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(SettingsScreen));
    expect(MarqueePalette.of(ctx), MarqueePalette.bordeaux);
    expect(find.text('المظهر'), findsOneWidget);
    expect(find.text('بوردو (أحمر)'), findsOneWidget);
  });
}
