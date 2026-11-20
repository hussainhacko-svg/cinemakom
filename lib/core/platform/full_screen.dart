import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// The desktop window's full screen (PLAYER.md §9.2) and size, through
/// window_manager's native API. The only file that imports it. Tests
/// override [fullScreenProvider] with a fake.
abstract interface class FullScreen {
  bool get isOn;

  /// Turning it off gives the window back its previous size.
  void set(bool on);
}

final fullScreenProvider = Provider<FullScreen>((ref) => _WindowFullScreen());

class _WindowFullScreen implements FullScreen {
  Window? get _window {
    try {
      return WindowManager.instance.getCurrent();
    } on Object {
      // No native window library here (a phone, tests).
      return null;
    }
  }

  @override
  bool get isOn {
    try {
      return _window?.isFullScreen ?? false;
    } on Object {
      return false;
    }
  }

  @override
  void set(bool on) {
    try {
      _window?.isFullScreen = on;
    } on Object {
      // Nothing to do.
    }
  }
}

/// Sizes the desktop window's content to [size] (logical pixels) and centres
/// it. Used for the TV UI on Linux, which is drawn at 960 × 540 like a TV
/// (docs/TV.md §6.1). Does nothing where there's no native window.
void setWindowContentSize(Size size) {
  try {
    WindowManager.instance.getCurrent()
      ?..contentSize = size.toNative()
      ..center();
  } on Object {
    // No native window library here (a phone, tests).
  }
}
