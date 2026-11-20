import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/tv/focus/tv_focusable.dart';

import 'demo_screen.dart';
import 'reachability.dart';
import 'tv_driver.dart';

// The focus rules of docs/TV.md §5.1 on the demo screen (demo_screen.dart),
// at the TV's 960 × 540.

const _arabic = Locale('ar');

/// Calls to SystemNavigator.pop (the app leaving).
final _exits = <String>[];

Future<TvDriver> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  List<String>? log,
}) async {
  await tester.binding.setSurfaceSize(const Size(960, 540));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') _exits.add('exit');
      return null;
    },
  );
  _exits.clear();
  await tester.pumpWidget(DemoApp(key: UniqueKey(), locale: locale, log: log));
  await tester.pumpAndSettle();
  return TvDriver(tester);
}

ScrollPosition _scrollOf(WidgetTester tester, String label) {
  final item = find.byWidgetPredicate(
    (w) => w is TvFocusable && w.label == label,
  );
  return Scrollable.of(tester.element(item)).position;
}

void main() {
  testWidgets('R11: focus starts on the initial zone', (tester) async {
    final tv = await _pump(tester);
    expect(tv.focused, 'Play');
  });

  testWidgets('R1, R5: moves are declared and skip disabled and hidden', (
    tester,
  ) async {
    final tv = await _pump(tester);
    await tv.right();
    expect(tv.focused, 'Favorite');
    await tv.right(); // Trailer is disabled
    expect(tv.focused, 'Quality 1080p');
    await tv.right(); // Hidden is inside ExcludeFocus
    expect(tv.focused, 'Quality 1080p');
    await tv.down();
    expect(tv.focused, 'Season 1');
    expect(tv.focusPath, '1/0:0');
  });

  testWidgets('R1, R2: the split; Down keeps the cell in a grid (§7.4)', (
    tester,
  ) async {
    final tv = await _pump(tester);
    await tv.down();
    await tv.down();
    await tv.down();
    expect(tv.focused, 'Season 3');
    await tv.right();
    expect(tv.focused, 'S3 Episode 1');
    await tv.right();
    expect(tv.focused, 'S3 Download 1');
    await tv.down();
    expect(tv.focused, 'S3 Download 2');
    await tv.down();
    expect(tv.focused, 'S3 Download 3');
    await tv.left();
    expect(tv.focused, 'S3 Episode 3');
    await tv.left(); // back to the selected season
    expect(tv.focused, 'Season 3');
    await tv.right(); // the episodes column remembers
    expect(tv.focused, 'S3 Episode 3');
  });

  testWidgets('R2: Down then Up comes back to the same card', (tester) async {
    final tv = await _pump(tester);
    await tv.focusLabel('Poster 0');
    await tv.right();
    await tv.right();
    await tv.right();
    expect(tv.focused, 'Poster 3');
    await tv.down();
    expect(tv.focused, 'Row A');
    await tv.up();
    expect(tv.focused, 'Poster 3');
  });

  testWidgets('R3: an arrow at an edge does nothing', (tester) async {
    final tv = await _pump(tester);
    await tv.left();
    expect(tv.focused, 'Play');
    await tv.up();
    expect(tv.focused, 'Play');
    await tv.focusLabel('Poster 0');
    await tv.left();
    expect(tv.focused, 'Poster 0');
    await tv.press(LogicalKeyboardKey.arrowRight, times: 25);
    expect(tv.focused, 'Poster 19');
  });

  testWidgets('R4, R9, R11: a panel opens on the current choice, keeps focus '
      'and gives it back', (tester) async {
    final tv = await _pump(tester);
    await tv.focusLabel('Quality 1080p');
    await tv.ok();
    expect(tv.focused, '1080p');
    await tv.up();
    expect(tv.focused, '4K');
    await tv.up(); // modal: Up at the top stays in the panel
    expect(tv.focused, '4K');
    await tv.back();
    expect(tv.focused, 'Quality 1080p');
    await tv.ok();
    await tv.down();
    await tv.ok();
    expect(tv.focused, 'Quality 720p');
  });

  testWidgets('R2, R4: a pushed page pops with Back, focus where it was', (
    tester,
  ) async {
    final tv = await _pump(tester);
    await tv.right();
    await tv.ok();
    expect(tv.focused, 'Pushed A');
    await tv.right();
    expect(tv.focused, 'Pushed B');
    await tv.back();
    expect(tv.focused, 'Favorite');
    await tv.back();
    expect(_exits, ['exit']);
  });

  testWidgets('R6: a long press is a shortcut; a press selects', (
    tester,
  ) async {
    final log = <String>[];
    final tv = await _pump(tester, log: log);
    await tv.focusLabel('Poster 2');
    await tv.ok();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(TvFocusable.longPress);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(log, ['open poster 2', 'menu poster 2']);
  });

  testWidgets('R7: focus moves on when its item goes away', (tester) async {
    final tv = await _pump(tester);
    await tv.focusLabel('Remove Row B');
    await tv.ok();
    expect(tv.focused, 'Remove Row C');
    await tv.focusLabel('Remove Row D');
    await tv.ok(); // the last one: the previous item
    expect(tv.focused, 'Remove Row C');
    await tv.ok();
    expect(tv.focused, 'Remove Row A');
    await tv.ok(); // the zone is empty: the next zone
    expect(tv.focused, 'Search');
  });

  testWidgets('R8: text input only after OK; Back returns to the zones', (
    tester,
  ) async {
    final tv = await _pump(tester);
    await tv.focusLabel('Remove Row D');
    await tv.down();
    expect(tv.focused, 'Search');
    expect(find.byType(EditableText), findsNothing);
    await tv.ok();
    expect(tv.focused, startsWith('not a TV item'));
    await tester.enterText(find.byType(EditableText), 'dune');
    await tv.left(); // moves the cursor, not the focus
    expect(find.byType(EditableText), findsOneWidget);
    await tv.back();
    expect(tv.focused, 'Search');
    expect(find.text('dune'), findsOneWidget);
    await tv.up();
    expect(tv.focused, 'Remove Row D');
  });

  testWidgets('R10: rows scroll the focused card to the keyline; a held '
      'arrow jumps', (tester) async {
    final tv = await _pump(tester);
    await tv.focusLabel('Poster 0');
    final row = _scrollOf(tester, 'Poster 0');
    await tv.press(LogicalKeyboardKey.arrowRight, times: 5);
    // The card (10 dp inside its slot) sits at the 48 dp keyline.
    expect(row.pixels, 5 * 130 + 10);
    // Held: each repeat lands at once, without waiting for an animation.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tv.focused, 'Poster 7');
    expect(row.pixels, 7 * 130 + 10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // Near the end the row stops at its end.
    await tv.press(LogicalKeyboardKey.arrowRight, times: 12);
    expect(row.pixels, row.maxScrollExtent);
  });

  testWidgets('R10: the page puts the focused zone at the keyline, and the '
      'first zone at the top', (tester) async {
    final tv = await _pump(tester);
    final page = _scrollOf(tester, 'Play');
    await tv.focusLabel('Poster 0');
    final header = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is TvFocusable && w.label == 'Poster 0'),
    );
    expect(page.pixels, greaterThan(0));
    // The zone's top (the row) sits at the keyline.
    expect(header.dy, closeTo(27 + 10, 1));
    await tv.up();
    expect(tv.focused, 'Season 1');
    await tv.focusLabel('Play');
    expect(page.pixels, 0);
  });

  testWidgets('R12: in Arabic, arrows follow what you see', (tester) async {
    final tv = await _pump(tester, locale: _arabic);
    await tv.right(); // Play is at the start, on the right
    expect(tv.focused, 'Play');
    await tv.left();
    expect(tv.focused, 'Favorite');
    await tv.down();
    expect(tv.focused, 'Season 1');
    await tv.left(); // the episodes are beside the seasons, to the left
    expect(tv.focused, 'S1 Episode 1');
    await tv.left();
    expect(tv.focused, 'S1 Download 1');
    await tv.right();
    expect(tv.focused, 'S1 Episode 1');
    await tv.right();
    expect(tv.focused, 'Season 1');
  });

  testWidgets('R7: the watchdog reports a focus lost on a screen with '
      'something to focus', (tester) async {
    final tv = await _pump(tester);
    expect(tv.focused, 'Play');
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect('$error', contains('TvFocusWatchdog'));
  });

  for (final locale in [const Locale('en'), _arabic]) {
    testWidgets('No traps (${locale.languageCode}): every control reached, '
        'Back always leaves', (tester) async {
      final reached = await expectNoTraps(
        tester,
        pumpScreen: () => _pump(tester, locale: locale),
        leftScreen: () => _exits.isNotEmpty,
      );
      expect(reached, contains('Search'));
      expect(reached, contains('Poster 19'));
      expect(reached, isNot(contains('Trailer')));
      expect(reached, isNot(contains('Hidden')));
    });
  }
}
