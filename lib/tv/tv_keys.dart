import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Back on the remote (Back, Esc on a keyboard). `TvApp` runs the Back
/// ladder for it (`tvHandleBack`, docs/TV.md §5.1 R4).
class TvBackIntent extends Intent {
  const TvBackIntent();
}

/// Play/pause on the remote, or Space on a keyboard. Only the player handles
/// it (TV-4); elsewhere it does nothing.
class TvPlayPauseIntent extends Intent {
  const TvPlayPauseIntent();
}

/// The keys that mean OK. `TvFocusable` reads them itself (it fires on key
/// up and tells a long press apart); outside one they activate.
final tvSelectKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// Every key the TV app reacts to, bound once here (docs/TV.md §5.2). This
/// replaces Flutter's defaults entirely, so nothing depends on how a Flutter
/// version happens to map `select`. The arrows aren't here on purpose: the
/// zones move focus (R1), and Flutter's geometric traversal never runs. Text
/// fields keep their own editing keys (`DefaultTextEditingShortcuts`).
const tvShortcuts = <ShortcutActivator, Intent>{
  // OK
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  // Back
  SingleActivator(LogicalKeyboardKey.goBack): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.escape): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.backspace): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonB): TvBackIntent(),
  // Media
  SingleActivator(LogicalKeyboardKey.space): TvPlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): TvPlayPauseIntent(),
};
