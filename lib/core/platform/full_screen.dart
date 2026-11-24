import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/scheduler.dart';
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
    void apply() {
      try {
        _window?.isFullScreen = on;
      } on Object {
        // Nothing to do.
      }
    }

    // On Windows, toggling full screen calls Win32 SetWindowPos synchronously,
    // which dispatches WM_SIZE and pumps a nested Flutter frame. Doing that
    // inside handleDrawFrame (e.g. PlayerScreen.dispose) clears the outer
    // frame's timestamp and throws on post-frame callbacks.
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      Timer.run(apply);
    } else {
      apply();
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
