import 'dart:convert';

import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/features/details/details_screen.dart';
import 'package:cinemakom/features/search/search_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_harness.dart';

MemoryPreferenceStore storeWith([List<String>? history]) =>
    MemoryPreferenceStore({
      PreferenceKeys.language: 'en',
      if (history != null) PreferenceKeys.searchHistory: jsonEncode(history),
    });

List<String> saved(MemoryPreferenceStore store) => [
  for (final q in jsonDecode(
    store.getString(PreferenceKeys.searchHistory) ?? '[]',
  ) as List)
    q as String,
];

Future<void> openSearch(
  WidgetTester tester,
  MemoryPreferenceStore store,
) async {
  await pumpApp(tester, store: store);
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the search key remembers a search; typing alone does not', (
    tester,
  ) async {
    final store = storeWith();
    await openSearch(tester, store);
    expect(find.text('RECENT SEARCHES'), findsNothing);

    await tester.enterText(find.byType(TextField), 'bat');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(saved(store), isEmpty, reason: 'searched while typing');

    await tester.enterText(find.byType(TextField), 'batman');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(saved(store), ['batman']);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT SEARCHES'), findsOneWidget);
    expect(find.text('batman'), findsOneWidget);
  });

  testWidgets('opening a result remembers the search', (tester) async {
    final store = storeWith();
    await openSearch(tester, store);
    await tester.enterText(find.byType(TextField), 'batman');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('The Batman'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Batman'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailsScreen), findsOneWidget);
    expect(saved(store), ['batman']);
  });

  testWidgets('a recent search searches again and moves to the top', (
    tester,
  ) async {
    final store = storeWith(['dune', 'batman']);
    await openSearch(tester, store);
    await tester.tap(find.text('batman'));
    await tester.pumpAndSettle();
    expect(find.text('The Batman'), findsOneWidget);
    expect(saved(store), ['batman', 'dune']);
  });

  testWidgets('one search or all of them can be removed', (tester) async {
    final store = storeWith(['dune', 'batman', 'friends']);
    await openSearch(tester, store);

    await tester.tap(find.byTooltip('Remove “batman”'));
    await tester.pumpAndSettle();
    expect(find.text('batman'), findsNothing);
    expect(find.text('dune'), findsOneWidget);
    expect(saved(store), ['dune', 'friends']);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT SEARCHES'), findsNothing);
    expect(find.text('dune'), findsNothing);
    expect(saved(store), isEmpty);
    // The genres are still there.
    expect(find.text('BROWSE GENRES'), findsOneWidget);
  });

  testWidgets('keeps the newest $searchHistoryLimit, without duplicates', (
    tester,
  ) async {
    final store = storeWith([
      for (var i = 0; i < searchHistoryLimit; i++) 'q$i',
    ]);
    await openSearch(tester, store);
    await tester.enterText(find.byType(TextField), '  Q3 ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final history = saved(store);
    expect(history, hasLength(searchHistoryLimit));
    expect(history.take(2), ['new', 'Q3']);
    expect(history, isNot(contains('q3')));
    expect(history, isNot(contains('q${searchHistoryLimit - 1}')));
  });

  testWidgets('a corrupt saved list is ignored', (tester) async {
    final store = MemoryPreferenceStore({
      PreferenceKeys.language: 'en',
      PreferenceKeys.searchHistory: '{not json',
    });
    await openSearch(tester, store);
    expect(find.text('RECENT SEARCHES'), findsNothing);
    expect(find.text('BROWSE GENRES'), findsOneWidget);
  });
}
