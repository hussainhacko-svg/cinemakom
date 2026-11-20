import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Back on the remote (Back, Esc on a keyboard). The Back ladder (docs/TV.md
/// §5.1 R4) handles it; until then [TvApp] pops the page or leaves the app.
class TvBackIntent extends Intent {
  const TvBackIntent();
}

/// Play/pause on the remote, or Space on a keyboard. Only the player handles
/// it (TV-4); elsewhere it does nothing.
class TvPlayPauseIntent extends Intent {
  const TvPlayPauseIntent();
}

/// Every key the TV app reacts to, bound once here (docs/TV.md §5.2). This
/// replaces Flutter's defaults entirely, so nothing depends on how a Flutter
/// version happens to map `select`. Text fields keep their own editing keys
/// (`DefaultTextEditingShortcuts` sits below this).
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
  // The arrows. TV-1 replaces these with the declared moves of TvZone (R1).
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
    TraversalDirection.up,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
    TraversalDirection.down,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
    TraversalDirection.left,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
    TraversalDirection.right,
  ),
  // Media
  SingleActivator(LogicalKeyboardKey.space): TvPlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): TvPlayPauseIntent(),
};
