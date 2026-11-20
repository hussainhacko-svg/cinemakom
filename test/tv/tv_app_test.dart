import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinemakom/tv/tv_app.dart';

void main() {
  testWidgets('the remote keys: arrows move, OK activates, Back exits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    await tester.pumpWidget(const TvApp());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Last key: OK 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Last key: OK 2'), findsOneWidget);

    // Esc stands in for the remote's Back (the same TvBackIntent): the test
    // key simulator has no physical key for Android's KEYCODE_BACK.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, contains('SystemNavigator.pop'));
  });
}
