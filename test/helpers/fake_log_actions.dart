import 'dart:io';

import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:cinemakom/features/settings/activity_log_flow.dart';

/// [ActivityLogActions] without the share sheet, a save dialog or a
/// socket: what was asked is recorded.
class FakeLogActions implements ActivityLogActions {
  final shared = <(File, String)>[];
  final saved = <File>[];
  final served = <File>[];
  int clears = 0;
  int closes = 0;

  /// Whether the device has a local network ([serve] gives `null` if not).
  bool network = true;

  /// Where the save dialog puts the copy; `null` is Cancel.
  String? saveTo = '/home/me/cinemakom-log.txt';

  /// Makes [export] fail.
  bool failExport = false;

  /// How long [export] takes (the real one writes a file).
  Duration exportDelay = Duration.zero;

  static final url = Uri.parse(
    'http://192.168.1.5:41234/0123456789abcdef0123456789abcdef/cinemakom-log.txt',
  );

  @override
  String? folder = '/storage/emulated/0/Android/data/cinemakom/files/logs';

  @override
  Future<File> export() async {
    if (exportDelay > Duration.zero) await Future<void>.delayed(exportDelay);
    if (failExport) throw const FileSystemException('disk full');
    return File('/tmp/cinemakom-log-test.txt');
  }

  @override
  Future<void> share(File file, {required String subject}) async =>
      shared.add((file, subject));

  @override
  Future<String?> saveCopy(File file, {required String confirm}) async {
    saved.add(file);
    return saveTo;
  }

  @override
  Future<LogShare?> serve(File file) async {
    served.add(file);
    if (!network) return null;
    return (url: url, close: () async => closes++);
  }

  @override
  Future<void> clear() async {
    clears++;
    await EventLog.instance.clear();
  }
}
