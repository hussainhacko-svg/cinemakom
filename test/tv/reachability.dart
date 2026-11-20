import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinemakom/tv/focus/tv_focusable.dart';

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
}) async {
  final semantics = tester.ensureSemantics();
  final tv = TvDriver(tester);
  await pumpScreen();
  final buttons = enabledButtons(tester);

  final start = tv.focused;
  expect(start, isNot(startsWith('not a TV item')), reason: 'No initial focus');
  final reached = <String>{start};
  final queue = [start];
  while (queue.isNotEmpty) {
    final from = queue.removeAt(0);
    for (final arrow in _arrows) {
      // Content changes as focus moves (a season shows its episodes): an
      // item that's gone was reached, and the new ones get explored.
      if (!_exists(from)) break;
      await tv.focusLabel(from);
      await tv.press(arrow);
      final to = tv.focused;
      expect(
        to,
        isNot(startsWith('not a TV item')),
        reason: '$arrow from "$from"',
      );
      if (reached.add(to)) queue.add(to);
    }
  }
  expect(buttons.difference(reached), isEmpty, reason: 'Unreachable controls');

  for (final label in reached) {
    await pumpScreen();
    // An item far along a lazy row isn't built on a fresh screen; Back
    // doesn't depend on where in a row focus is.
    if (!_exists(label)) continue;
    await tv.focusLabel(label);
    var presses = 0;
    while (!leftScreen() && presses < maxBack) {
      await tv.back();
      presses++;
    }
    expect(leftScreen(), isTrue, reason: 'Back from "$label" never left');
  }
  semantics.dispose();
  return reached;
}

bool _exists(String label) => find
    .byWidgetPredicate((w) => w is TvFocusable && w.label == label)
    .evaluate()
    .isNotEmpty;
