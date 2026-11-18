import 'dart:convert';
import 'dart:io';

/// Decoded JSON of `test/fixtures/<name>.json` (captured by
/// `tool/capture_fixtures.dart`).
Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
