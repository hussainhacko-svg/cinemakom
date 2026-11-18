// Live check of every endpoint through the repositories, using the debug
// screen. Needs network access:
//
//   fvm flutter test integration_test/api_debug_test.dart -d linux
import 'package:cinemakom/features/debug/debug_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every endpoint returns data', (tester) async {
    tester.view.physicalSize = const Size(800, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DebugScreen())),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final report = <String>[];
    final failed = <String>[];
    for (final tile in tiles) {
      final name = (tile.title! as Text).data!;
      final detail = (tile.subtitle! as Text).data!;
      final icon = (tile.leading is Icon) ? (tile.leading! as Icon).icon : null;
      final status = switch (icon) {
        Icons.check_circle => 'OK   ',
        Icons.remove_circle_outline => 'EMPTY',
        Icons.error => 'ERROR',
        _ => 'WAIT ',
      };
      if (status == 'ERROR' || status == 'WAIT ') failed.add(name);
      report.add('$status $name: ${detail.split('\n').take(2).join(' | ')}');
    }
    // ignore: avoid_print
    print(report.join('\n'));
    expect(tiles, isNotEmpty);
    expect(failed, isEmpty, reason: 'Failed or timed out: $failed');
  });
}
