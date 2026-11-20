import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Back from a keyboard (Esc, Backspace, gamepad B). `TvApp` runs the Back
/// ladder for it (`tvHandleBack`, docs/TV.md §5.1 R4), as it does for the
/// remote's Back.
class TvBackIntent extends Intent {
  const TvBackIntent();
}

/// The remote's media keys (Space on a keyboard is play/pause).
enum TvMediaKey { playPause, play, pause, rewind, fastForward, next }

/// A media key. `TvApp` hands it to [TvMedia.handler]: the open player's,
/// so the keys work over its panels too. Elsewhere they do nothing.
class TvMediaIntent extends Intent {
  const TvMediaIntent(this.key);

  final TvMediaKey key;
}

/// Who gets the media keys: the player while it's open (docs/TV.md §8.1:
/// they always work, controls shown or not).
abstract final class TvMedia {
  static void Function(TvMediaKey key)? handler;
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
  // Back from a keyboard. The remote's Back isn't here: Android sends it to
  // the app twice (as a key and as the system Back), so it comes in once,
  // as the system Back (`TvApp.didPopRoute`).
  SingleActivator(LogicalKeyboardKey.escape): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.backspace): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonB): TvBackIntent(),
  // Media
  SingleActivator(LogicalKeyboardKey.space): TvMediaIntent(
    TvMediaKey.playPause,
  ),
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): TvMediaIntent(
    TvMediaKey.playPause,
  ),
  SingleActivator(LogicalKeyboardKey.mediaPlay): TvMediaIntent(TvMediaKey.play),
  SingleActivator(LogicalKeyboardKey.mediaPause): TvMediaIntent(
    TvMediaKey.pause,
  ),
  SingleActivator(LogicalKeyboardKey.mediaRewind): TvMediaIntent(
    TvMediaKey.rewind,
  ),
  SingleActivator(LogicalKeyboardKey.mediaFastForward): TvMediaIntent(
    TvMediaKey.fastForward,
  ),
  SingleActivator(LogicalKeyboardKey.mediaTrackNext): TvMediaIntent(
    TvMediaKey.next,
  ),
};
