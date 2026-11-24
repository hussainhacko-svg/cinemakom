import 'dart:io' as io;

import 'package:file/file.dart' show File;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

import '../platform/app_dirs.dart';

/// The posters' disk cache, for every `CachedNetworkImage` and
/// `CachedNetworkImageProvider`. On desktop it's in the cache folder
/// (`~/.cache/<id>/images`, docs/PACKAGING.md §2), with its index: the
/// package's default is the temp folder, which Linux empties at every
/// reboot (and keeps in RAM on tmpfs) while the index stayed in the data
/// folder. Android keeps the package's default.
BaseCacheManager get appImageCache => _cache ??= _create();

BaseCacheManager? _cache;

BaseCacheManager _create() {
  final dirs = AppDirs.current;
  if (dirs == null) return DefaultCacheManager();
  return CacheManager(
    Config(
      'images',
      repo: JsonCacheInfoRepository.withFile(
        io.File(p.join(dirs.cache, 'images.json')),
      ),
      fileSystem: FolderFileSystem(p.join(dirs.cache, 'images')),
    ),
  );
}

/// Cache files in [path], created when needed.
class FolderFileSystem implements FileSystem {
  FolderFileSystem(this.path);

  final String path;

  static const _fs = LocalFileSystem();

  @override
  Future<File> createFile(String name) async {
    final dir = _fs.directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.childFile(name);
  }
}
