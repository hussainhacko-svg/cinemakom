// Settings → Help → Activity log on TV: the newest entries, and the log
// opened on a phone through a QR code (a TV has no share sheet).
import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/tv/screens/settings/tv_activity_log_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_log_actions.dart';
import 'reachability.dart';
import 'tv_driver.dart';

/// Each time the app asked to exit (Back past the last screen).
final _exits = <String>[];

/// The TV app, then Settings → Activity log by remote.
Future<(TvDriver, FakeLogActions)> _open(
  WidgetTester tester, {
  bool arabic = false,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') _exits.add('exit');
      return null;
    },
  );
  _exits.clear();
  final actions = FakeLogActions();
  await tester.pumpWidget(const SizedBox());
  await pumpApp(
    tester,
    tv: true,
    logActions: actions,
    store: MemoryPreferenceStore({
      PreferenceKeys.language: arabic ? 'ar' : 'en',
    }),
  );
  final tv = TvDriver(tester);
  await tv.up();
  for (var i = 0; i < 4; i++) {
    // The tabs run along the reading direction (R12).
    arabic ? await tv.left() : await tv.right();
  }
  await tv.down();
  await tv.focusLabel(arabic ? 'سجل النشاط' : 'Activity log');
  await tv.ok();
  expect(find.byType(TvActivityLogScreen), findsOneWidget);
  return (tv, actions);
}

void main() {
  testWidgets('opens on "Open it on your phone"; the newest entries show', (
    tester,
  ) async {
    EventLog.instance
      ..record('player', 'phase loading → ready')
      ..record('error', 'Bad state: no frame');
    final (tv, actions) = await _open(tester);
    expect(tv.focused, 'Open it on your phone');
    expect(find.textContaining('Bad state: no frame'), findsOneWidget);
    expect(find.textContaining('adb pull ${actions.folder}'), findsOneWidget);
    await tv.right();
    expect(tv.focused, 'Clear');
  });

  testWidgets('the phone: a QR code for the log while the panel is open', (
    tester,
  ) async {
    final (tv, actions) = await _open(tester);
    await tv.ok();
    expect(actions.served, hasLength(1));
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.semanticsLabel, 'Activity log');
    expect(find.textContaining('same Wi-Fi'), findsOneWidget);
    expect(find.text('192.168.1.5:41234'), findsOneWidget);
    expect(actions.closes, 0);

    await tv.back();
    expect(find.byType(QrImageView), findsNothing);
    expect(actions.closes, 1, reason: 'closed with the panel');
    expect(tv.focused, 'Open it on your phone');
  });

  // Live, the log file takes a moment to write before the panel opens; the
  // screen goes on rebuilding with new entries meanwhile.
  testWidgets('a slow export: the focus goes into the panel and back', (
    tester,
  ) async {
    final (tv, actions) = await _open(tester);
    actions.exportDelay = const Duration(milliseconds: 300);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 10; i++) {
      EventLog.instance.record('player', 'tick $i');
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tv.focused, 'OK');
    EventLog.instance.record('player', 'while the panel is open');
    await tester.pumpAndSettle();
    expect(tv.focused, 'OK');
    await tv.back();
    expect(tv.focused, 'Open it on your phone');
  });

  // Remotes send Select or Enter for OK (the live test sends Enter).
  testWidgets('Enter opens one panel, and Back closes it', (tester) async {
    final (tv, actions) = await _open(tester);
    actions.exportDelay = const Duration(milliseconds: 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(actions.served, hasLength(1));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tv.focused, 'OK');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(tv.focused, 'Open it on your phone');
  });

  // The live screenshot run's keys: Enter on the row, Enter on the button,
  // Escape out of the panel, Escape back to Settings.
  testWidgets('Back from it returns to its row in Settings', (tester) async {
    final (tv, _) = await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tv.focused, 'OK');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tv.focused, 'Open it on your phone');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TvActivityLogScreen), findsNothing);
    expect(tv.focused, 'Activity log');
  });

  testWidgets('no Wi-Fi says so', (tester) async {
    final (tv, actions) = await _open(tester);
    actions.network = false;
    await tv.ok();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('Connect the TV to Wi-Fi'), findsOneWidget);
  });

  testWidgets('Clear empties it', (tester) async {
    EventLog.instance.record('player', 'something');
    final (tv, actions) = await _open(tester);
    await tv.right();
    await tv.ok();
    expect(actions.clears, 1);
    expect(find.text('The log is empty now'), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  for (final arabic in [false, true]) {
    testWidgets('no traps (${arabic ? 'Arabic' : 'English'})', (tester) async {
      await expectNoTraps(
        tester,
        pumpScreen: () async => (await _open(tester, arabic: arabic)).$1,
        leftScreen: () => _exits.isNotEmpty,
      );
    });
  }
}
