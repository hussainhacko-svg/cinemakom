import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Hands a file to a phone on the same Wi-Fi: the TV's way to get its log
/// out (a TV has no share sheet), shown as a QR code. Only while it's
/// open, only at a random address nobody can guess, and only the one file.
class LogServer {
  LogServer._(this._server, this.address, this._file, this._token)
    : url = Uri(
        scheme: 'http',
        host: address.address,
        port: _server.port,
        path: '/$_token/cinemakom-log.txt',
      );

  final HttpServer _server;
  final File _file;
  final String _token;

  /// The device's address on the local network.
  final InternetAddress address;

  /// What the phone opens.
  final Uri url;

  Timer? _closeTimer;
  bool _closed = false;

  /// Serves [file] until [close], or for [lifetime] at most. `null` when
  /// the device has no local network address (no Wi-Fi or Ethernet).
  /// [address] picks one in tests (the loopback).
  static Future<LogServer?> start(
    File file, {
    Duration lifetime = const Duration(minutes: 10),
    InternetAddress? address,
  }) async {
    final where = address ?? await localAddress();
    if (where == null) return null;
    final HttpServer server;
    try {
      server = await HttpServer.bind(where, 0);
    } on SocketException {
      return null;
    }
    final random = Random.secure();
    final token = [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final s = LogServer._(server, where, file, token);
    server.listen(s._handle, onError: (_) {});
    s._closeTimer = Timer(lifetime, s.close);
    return s;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' ||
          request.uri.path != '/$_token/cinemakom-log.txt') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (!await _file.exists()) {
        response.statusCode = HttpStatus.gone;
        return;
      }
      response.headers
        ..contentType = ContentType('text', 'plain', charset: 'utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      await response.addStream(_file.openRead());
    } on Object {
      // Halfway through the file the headers are gone: the answer just
      // ends there.
    } finally {
      try {
        await response.close();
      } on Object {
        // The phone went away.
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closeTimer?.cancel();
    await _server.close(force: true);
  }

  /// The first private IPv4 address of a network interface (Wi-Fi or
  /// Ethernet), or `null`.
  static Future<InternetAddress?> localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (_isPrivate(a)) return a;
        }
      }
    } on Object {
      // No network.
    }
    return null;
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    if (b.length != 4 || a.isLoopback) return false;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
}
