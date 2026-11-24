import 'dart:io';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/diagnostics/event_log.dart';
import '../../core/diagnostics/log_server.dart';

// Settings → Help → Activity log, shared by the phone and TV UIs: the
// flight recorder's entries (lib/core/diagnostics), and getting the file
// off the device: the share sheet on phones, a save dialog on computers,
// a QR code for a phone on the same Wi-Fi on the TV.

/// The entries of this session, the newest first, as they come.
final activityLogProvider = StreamProvider.autoDispose<List<LogEntry>>((
  ref,
) async* {
  final log = EventLog.instance;
  yield log.recent.reversed.toList();
  await for (final _ in log.changes) {
    yield log.recent.reversed.toList();
  }
});

/// The log served on the Wi-Fi: what the phone opens, and how to stop.
typedef LogShare = ({Uri url, Future<void> Function() close});

/// What can be done with the log. A provider, so tests (where platform
/// channels never answer) swap it.
final activityLogActionsProvider = Provider<ActivityLogActions>(
  (ref) => const DeviceLogActions(),
);

abstract interface class ActivityLogActions {
  /// One text file with this session and the last one.
  Future<File> export();

  /// The share sheet (phones).
  Future<void> share(File file, {required String subject});

  /// A save dialog (computers): where it went, or `null` if cancelled.
  Future<String?> saveCopy(File file, {required String confirm});

  /// Serves [file] to a phone on the same Wi-Fi (TV), or `null` without a
  /// local network.
  Future<LogShare?> serve(File file);

  Future<void> clear();

  /// Where the log files are, for `adb pull`; `null` before they exist.
  String? get folder;
}

class DeviceLogActions implements ActivityLogActions {
  const DeviceLogActions();

  @override
  Future<File> export() async => EventLog.instance.export(
    Directory('${(await getTemporaryDirectory()).path}/activity-log'),
  );

  @override
  Future<void> share(File file, {required String subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: subject,
        title: subject,
      ),
    );
  }

  @override
  Future<String?> saveCopy(File file, {required String confirm}) async {
    final name = file.uri.pathSegments.last;
    final to = await files.getSaveLocation(
      suggestedName: name,
      confirmButtonText: confirm,
      acceptedTypeGroups: const [
        files.XTypeGroup(label: 'Text', extensions: ['txt']),
      ],
    );
    if (to == null) return null;
    await file.copy(to.path);
    return to.path;
  }

  @override
  Future<LogShare?> serve(File file) async {
    final server = await LogServer.start(file);
    return server == null ? null : (url: server.url, close: server.close);
  }

  @override
  Future<void> clear() => EventLog.instance.clear();

  @override
  String? get folder => EventLog.instance.directory?.path;
}
