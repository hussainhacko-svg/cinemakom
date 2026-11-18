import 'package:flutter/foundation.dart';

/// Platform checks used across the app. Use these instead of `dart:io`
/// `Platform` so the logic stays testable via [debugDefaultTargetPlatformOverride].
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
