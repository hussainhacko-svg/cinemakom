import 'dart:io';

import 'package:cinemakom/app/brand/brand_paths.g.dart';
import 'package:cinemakom/app/brand/cinemakom_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('every mark path builds and stays inside its 100×100 box', () {
    for (final ops in [fullMarkOps, smallMarkOps, tinyMarkOps]) {
      final bounds = buildMarkPath(ops).getBounds();
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(100));
      expect(bounds.bottom, lessThanOrEqualTo(100));
      expect(bounds.width, greaterThan(70));
    }
  });

  test('the ك and perforation are holes (even-odd), not filled', () {
    final full = buildMarkPath(fullMarkOps);
    expect(full.fillType, PathFillType.evenOdd);
    expect(full.contains(const Offset(20, 50)), isTrue); // solid ticket edge
    expect(full.contains(const Offset(68, 50.5)), isFalse); // a perforation dot
    expect(full.contains(const Offset(95, 50)), isFalse); // outside
  });

  test('detail follows size', () {
    expect(CinemakomMark.detailFor(96), MarkDetail.full);
    expect(CinemakomMark.detailFor(48), MarkDetail.full);
    expect(CinemakomMark.detailFor(32), MarkDetail.small);
    expect(CinemakomMark.detailFor(16), MarkDetail.tiny);
  });

  test('generated platform assets exist', () {
    for (final path in [
      'branding/mark-full.svg',
      'branding/store/play-store-512.png',
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
      'android/app/src/main/res/values-v31/styles.xml',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      'windows/runner/resources/app_icon.ico',
      'linux/packaging/icons/hicolor/scalable/apps/io.github.sharon_xa.cinemakom.svg',
      'linux/packaging/io.github.sharon_xa.cinemakom.desktop',
      'assets/brand/app_icon_256.png',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('<monochrome'));
    expect(
      Directory('android/app/src/main/res/values-night').existsSync(),
      isFalse,
    );
  });

  testWidgets('the mark paints at several sizes without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            CinemakomMark(size: 16),
            CinemakomMark(size: 32),
            CinemakomMark(size: 96),
          ],
        ),
      ),
    );
    expect(find.byType(CinemakomMark), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
