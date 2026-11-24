import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/diagnostics/event_log.dart';
import 'tv_focusable.dart';

/// The remote's keys in the flight recorder, each with what had the focus
/// when it was pressed (before the screen reacted). A held key is one
/// line, then how many repeats it sent. Keys that type a character (a
/// remote with a keyboard, in Search) are never written down.
abstract final class TvKeyLog {
  static bool _on = false;
  static LogicalKeyboardKey? _held;
  static int _repeats = 0;

  static void start() {
    if (_on) return;
    _on = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static void stop() {
    if (!_on) return;
    _on = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  static bool _onKey(KeyEvent event) {
    final character = event.character;
    if (character != null && character.trim().isNotEmpty) return false;
    final key = event.logicalKey;
    switch (event) {
      case KeyDownEvent():
        _held = key;
        _repeats = 0;
        logEvent('key', '${keyName(key)} on ${describeTvFocus()}');
      case KeyRepeatEvent():
        if (key == _held) _repeats++;
      case KeyUpEvent():
        if (key == _held && _repeats > 0) {
          logEvent(
            'key',
            '${keyName(key)} held: $_repeats repeats, now on '
                '${describeTvFocus()}',
          );
        }
        if (key == _held) _held = null;
    }
    return false;
  }
}

/// "Arrow Up", "Select", "Media Play Pause" (release builds have no debug
/// names).
String keyName(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  return label.trim().isEmpty ? 'key 0x${key.keyId.toRadixString(16)}' : label;
}

/// The label of the focused [TvFocusable] ("'Skip intro'"), or what else
/// has the focus.
String describeTvFocus() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'nothing';
  final label = node.context
      ?.findAncestorWidgetOfExactType<TvFocusable>()
      ?.label;
  if (label != null) return "'$label'";
  return node.debugLabel ?? node.runtimeType.toString();
}
