import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_driver.dart';

/// The labels of every enabled button on screen, from the semantics tree.
Set<String> enabledButtons(WidgetTester tester) {
  final labels = <String>{};
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    if (flags.isButton &&
        flags.isEnabled != Tristate.isFalse &&
        !node.isInvisible &&
        data.label.isNotEmpty) {
      labels.add(data.label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root =
      tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return labels;
}

const _arrows = [
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
];

/// The no-trap check of docs/TV.md §5.3, for the screen [pumpScreen] shows:
/// 1. from the initial focus, trying every arrow from every item reached
///    (a breadth-first search) reaches every enabled control on screen;
/// 2. pressing Back again and again from any reached item leaves the screen
///    ([leftScreen] says when);
/// 3. the focus watchdog never fires (it fails the test by itself).
/// Returns the labels reached.
Future<Set<String>> expectNoTraps(
  WidgetTester tester, {
  required Future<void> Function() pumpScreen,
  required bool Function() leftScreen,
  int maxBack = 10,
  int? backChecks,
}) async {
  final semantics = tester.ensureSemantics();
  final tv = TvDriver(tester);
  await pumpScreen();
  final buttons = enabledButtons(tester);

  final start = tv.focusPath;
  expect(start, isNot(startsWith('not a TV item')), reason: 'No initial focus');
  // Explored by place in the zone tree; labels only say what was reached.
  final reached = <String, String>{start: tv.focused};
  final queue = [start];
  while (queue.isNotEmpty) {
    final from = queue.removeAt(0);
    for (final arrow in _arrows) {
      // Moving onto a tab shows another tab; start the screen again to come
      // back. Content that changes as focus moves (a season shows its
      // episodes) can be gone for good: it was reached, and the new items
      // get explored.
      if (!await tv.focusAt(from)) {
        await pumpScreen();
        if (!await tv.focusAt(from)) break;
      }
      await tv.press(arrow);
      final to = tv.focusPath;
      expect(
        to,
        isNot(startsWith('not a TV item')),
        reason: '$arrow from $from',
      );
      if (!reached.containsKey(to)) {
        reached[to] = tv.focused;
        queue.add(to);
      }
    }
  }
  final labels = reached.values.toSet();
  expect(buttons.difference(labels), isEmpty, reason: 'Unreachable controls');

  // Back from every reached item, or from [backChecks] of them spread over
  // the screen (a fresh screen per check is slow on a long Home).
  final all = reached.keys.toList();
  final step = backChecks == null || backChecks >= all.length
      ? 1
      : all.length ~/ backChecks;
  for (var k = 0; k < all.length; k += step) {
    final path = all[k];
    await pumpScreen();
    // An item far along a lazy row isn't built on a fresh screen; Back
    // doesn't depend on where in a row focus is.
    if (!await tv.focusAt(path)) continue;
    var presses = 0;
    while (!leftScreen() && presses < maxBack) {
      await tv.back();
      presses++;
    }
    expect(
      leftScreen(),
      isTrue,
      reason: 'Back from ${reached[path]} ($path) never left',
    );
  }
  semantics.dispose();
  return labels;
}
