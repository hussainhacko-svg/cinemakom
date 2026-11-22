import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What a download needs to continue from its partial file after
/// background_downloader gave up on it (docs/DOWNLOADS.md §5.5).
///
/// The engine clears a task's resume data when it fails for good: after 10
/// retries on a bad connection, or after Android stopped it (the 6-hour
/// limit on background work) and wouldn't let it start again. The partial
/// file is still on disk, but nothing refers to it any more, so Retry would
/// start a 27 GB download over. The engine's resume data is kept here
/// instead, and given back on Retry.
///
/// Entries are raw JSON so this file needs no library types. Writes are
/// serialized; a corrupt or missing file is an empty store.
class KeptResumeStore {
  KeptResumeStore(this._path);

  final Future<String> Function() _path;
  Map<String, Map<String, dynamic>>? _entries;
  Future<void> _writes = Future.value();

  Future<Map<String, Map<String, dynamic>>>? _loading;

  /// The entries, read from disk once (concurrent callers share the read).
  Future<Map<String, Map<String, dynamic>>> _load() =>
      _loading ??= _read().then((e) => _entries = e);

  Future<Map<String, Map<String, dynamic>>> _read() async {
    try {
      final file = File(await _path());
      if (!file.existsSync()) return {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return {};
      return {
        for (final e in json.entries)
          if (e.key is String && e.value is Map)
            e.key as String: Map<String, dynamic>.from(e.value as Map),
      };
    } on Object {
      return {}; // Unreadable: start empty.
    }
  }

  void _save() {
    final snapshot = jsonEncode(_entries ?? const {});
    _writes = _writes.then((_) async {
      try {
        final file = File(await _path());
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(snapshot, flush: true);
        await tmp.rename(file.path);
      } on Object {
        // Best effort: the next change writes again.
      }
    });
  }

  /// Keeps [resume] (the engine's resume data as JSON) for [taskId], when
  /// its partial file at [tempPath] holds [startByte] bytes or more.
  Future<void> keep(
    String taskId,
    Map<String, dynamic> resume, {
    required String tempPath,
    required int startByte,
  }) async {
    if (startByte <= 0 || !_holds(tempPath, startByte)) return;
    (await _load())[taskId] = {
      'resume': resume,
      'path': tempPath,
      'start': startByte,
    };
    _save();
  }

  /// [taskId]'s kept resume data, when its partial file is still there and
  /// long enough; otherwise forgets it.
  Future<Map<String, dynamic>?> usable(String taskId) async {
    final entries = await _load();
    final e = entries[taskId];
    if (e == null) return null;
    final path = e['path'];
    final start = e['start'];
    final resume = e['resume'];
    if (path is String &&
        start is int &&
        resume is Map &&
        _holds(path, start)) {
      return Map<String, dynamic>.from(resume);
    }
    entries.remove(taskId);
    _save();
    return null;
  }

  Future<void> remove(String taskId) async {
    if ((await _load()).remove(taskId) != null) _save();
  }

  /// The partial files of the kept tasks in [taskIds], by task ID. Entries
  /// of any other task (its download is gone or finished) are forgotten.
  Future<Map<String, String>> tempPaths(Set<String> taskIds) async {
    final entries = await _load();
    final stale = [
      for (final id in entries.keys)
        if (!taskIds.contains(id)) id,
    ];
    if (stale.isNotEmpty) {
      stale.forEach(entries.remove);
      _save();
    }
    return {
      for (final e in entries.entries)
        if (e.value['path'] case final String path when File(path).existsSync())
          e.key: path,
    };
  }

  /// Waits for pending writes (tests).
  Future<void> flush() => _writes;

  static bool _holds(String path, int bytes) {
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() >= bytes;
    } on FileSystemException {
      return false;
    }
  }
}
