// What the phone and TV apps write in the flight recorder as they're used:
// the screens, and on the TV each remote key with what had the focus.
import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../tv/tv_driver.dart';

List<String> lines(String tag) => [
  for (final e in EventLog.instance.recent)
    if (e.tag == tag) e.message,
];

void main() {
  testWidgets('the phone: each screen', (tester) async {
    await pumpApp(tester);
    expect(lines('route'), contains('/home'));
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(lines('route').last, '/search');
  });

  group('the TV', () {
    Future<TvDriver> open(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, tv: true);
      return TvDriver(tester);
    }

    testWidgets('each key, with what had the focus when it was pressed', (
      tester,
    ) async {
      final tv = await open(tester);
      expect(tv.focused, 'Play');
      await tv.up();
      await tv.right();
      expect(lines('key'), ["Arrow Up on 'Play'", "Arrow Right on 'Home'"]);
      expect(lines('route').last, '/search');
    });

    testWidgets('a held key is one line, then its repeats', (tester) async {
      await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(lines('key'), hasLength(2));
      expect(lines('key').first, startsWith('Arrow Down on '));
      expect(
        lines('key').last,
        startsWith('Arrow Down held: 4 repeats, now on '),
      );
    });

    testWidgets('typed characters are never written down', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.pumpAndSettle();
      expect(lines('key'), isEmpty);
    });

    testWidgets('media keys and Back are', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(lines('key'), [
        "Media Play Pause on 'Play'",
        startsWith('Escape on '),
      ]);
    });
  });
}
