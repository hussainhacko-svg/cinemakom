import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/features/library/widgets/continue_card.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_harness.dart';

/// The fixture movie (Eve of Destruction), 14 minutes into 100.
MemoryLibraryRepository watchedMovie() => MemoryLibraryRepository([
  WatchProgress(
    videoId: '3119279',
    position: const Duration(minutes: 86),
    duration: const Duration(minutes: 100),
    updatedAt: DateTime(2026, 11, 19),
    title: const LocalizedText(en: 'Eve of Destruction'),
    kind: VideoKind.movies,
  ),
]);

void main() {
  testWidgets('Details offers Resume with the time left', (tester) async {
    await pumpApp(tester, library: watchedMovie());
    ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
        .read(routerProvider)
        .push('/home/title/3119279');
    await tester.pumpAndSettle();
    expect(find.text('Resume · 14 min left'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('Home shows Continue watching, and a card plays it', (
    tester,
  ) async {
    await pumpApp(tester, library: watchedMovie());
    await tester.scrollUntilVisible(
      find.byType(ContinueCard),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CONTINUE WATCHING'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ContinueCard),
        matching: find.text('14 min left'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(ContinueCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PlayerScreen), findsOneWidget);
  });
}
