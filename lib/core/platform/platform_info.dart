import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _platformChannel = MethodChannel('io.github.sharon_xa.cinemakom/platform');

bool _isTv = false;

/// Test override for [isTv], mirroring [debugDefaultTargetPlatformOverride].
@visibleForTesting
bool? debugIsTvOverride;

/// Queries native platform flags once at startup (currently Android TV
/// Leanback / television UI mode, docs/TV.md).
Future<void> initPlatformInfo() async {
  if (!isAndroid) {
    _isTv = false;
    return;
  }
  try {
    _isTv = (await _platformChannel.invokeMethod<bool>('isTv')) ?? false;
  } on Object {
    _isTv = false;
  }
}

/// Platform checks used across the app. Use these instead of `dart:io`
/// `Platform` so the logic stays testable via [debugDefaultTargetPlatformOverride]
/// and [debugIsTvOverride].
bool get isDesktop =>
    switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS => true,
      _ => false,
    } &&
    !kIsWeb;

bool get isMobile =>
    switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    } &&
    !kIsWeb;

bool get isAndroid =>
    defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

/// True when running on Android TV / Google TV.
bool get isTv => (debugIsTvOverride ?? _isTv) && !kIsWeb;

/// True on touch phones and tablets (Android/iOS excluding Android TV).
bool get isTouchMobile => isMobile && !isTv;
