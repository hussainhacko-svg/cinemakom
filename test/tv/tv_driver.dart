import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/tv/focus/tv_focusable.dart';
import 'package:cinemakom/tv/focus/tv_nav.dart';

/// Presses remote keys in widget tests (docs/TV.md §5.3) and says where
/// focus is. Each press settles, so focus and scrolling are done after it.
class TvDriver {
  TvDriver(this.tester);

  final WidgetTester tester;

  Future<void> up() => press(LogicalKeyboardKey.arrowUp);
  Future<void> down() => press(LogicalKeyboardKey.arrowDown);
  Future<void> left() => press(LogicalKeyboardKey.arrowLeft);
  Future<void> right() => press(LogicalKeyboardKey.arrowRight);
  Future<void> ok() => press(LogicalKeyboardKey.select);

  /// Esc: the remote's Back, which the test key simulator can't make.
  Future<void> back() => press(LogicalKeyboardKey.escape);

  Future<void> press(LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  /// Holds [key] for [repeats] key repeats, one frame apart, then lets go.
  Future<void> hold(LogicalKeyboardKey key, {int repeats = 5}) async {
    await tester.sendKeyDownEvent(key);
    await tester.pump();
    for (var i = 0; i < repeats; i++) {
      await tester.sendKeyRepeatEvent(key);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// The label of the focused `TvFocusable`, or a description of what else
  /// has focus.
  String get focused {
    final node = FocusManager.instance.primaryFocus;
    final label = node?.context
        ?.findAncestorWidgetOfExactType<TvFocusable>()
        ?.label;
    if (node is TvItemNode && label != null) return label;
    return 'not a TV item: $node';
  }

  /// Where focus is in the zone tree: each group's order, then the zone's
  /// order and the item's index ("1/0:3").
  String get focusPath {
    final node = FocusManager.instance.primaryFocus;
    if (node is! TvItemNode || node.zone == null) return focused;
    final zone = node.zone!;
    final index = zone.indexes.firstWhere((i) => zone.itemAt(i)?.node == node);
    final orders = <int>[zone.order];
    for (var g = zone.parent; g != null && g.parent != null; g = g.parent) {
      orders.insert(0, g.order);
    }
    return '${orders.join('/')}:$index';
  }

  /// Focuses the item labelled [label] directly (to start a check there).
  Future<void> focusLabel(String label) async {
    final item = find.byWidgetPredicate(
      (w) => w is TvFocusable && w.label == label,
    );
    expect(item, findsOneWidget, reason: 'No TV item "$label"');
    final focus = tester.widget<Focus>(
      find.descendant(of: item, matching: find.byType(Focus)).first,
    );
    focus.focusNode!.requestFocus();
    await tester.pumpAndSettle();
  }
}
