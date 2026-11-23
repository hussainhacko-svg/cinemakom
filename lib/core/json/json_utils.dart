/// Tolerant JSON readers for the Cinemana API.
///
/// The API sends numbers as strings (and sometimes the other way round),
/// uses the string "null", and renames keys between endpoints. None of these
/// helpers throw.
library;

typedef JsonMap = Map<String, Object?>;

/// [value] as a map, or `null`.
JsonMap? asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return null;
}

/// [value] as a list. Anything else becomes an empty list.
List<Object?> asList(Object? value) => value is List ? value : const [];

/// A trimmed, non-empty string. Numbers and bools are stringified. Blank
/// strings and the literal "null" become `null`.
String? readString(Object? value) {
  final String s;
  if (value is String) {
    s = value.trim();
  } else if (value is num || value is bool) {
    s = value.toString();
  } else {
    return null;
  }
  if (s.isEmpty || s.toLowerCase() == 'null') return null;
  return s;
}

/// The first of [keys] in [map] with a non-blank value.
String? firstNonBlank(JsonMap map, List<String> keys) {
  for (final key in keys) {
    final s = readString(map[key]);
    if (s != null) return s;
  }
  return null;
}

/// An int from an int, a double, or a string like "12", "12.0" or "S02".
int? parseIntLoose(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.round() : null;
  final s = readString(value);
  if (s == null) return null;
  final asInt = int.tryParse(s);
  if (asInt != null) return asInt;
  // "1e400" and "NaN" parse as doubles that can't be rounded.
  final asDouble = double.tryParse(s);
  if (asDouble != null) return asDouble.isFinite ? asDouble.round() : null;
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

/// A double from a number or a string like "7.5" or "7.5/10".
double? parseDoubleLoose(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  final s = readString(value);
  if (s == null) return null;
  final direct = double.tryParse(s);
  if (direct != null) return direct.isFinite ? direct : null;
  final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return match == null ? null : double.tryParse(match[0]!);
}

/// true/false from bools, 1/0, and "true"/"false"/"1"/"0".
bool? parseBoolLoose(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch (readString(value)?.toLowerCase()) {
    'true' || '1' || 'yes' => true,
    'false' || '0' || 'no' => false,
    _ => null,
  };
}

/// The first non-blank string under [keys], or `null`. Also undoes `\/`
/// escapes that survive decoding in some responses.
String? readUrl(JsonMap map, List<String> keys) {
  final s = firstNonBlank(map, keys);
  return s == null ? null : unescapeUrl(s);
}

String unescapeUrl(String url) => url.replaceAll(r'\/', '/').trim();

/// True for absolute http(s) URLs. The API sometimes sends placeholders such
/// as `defaultImages/loading.gif` instead of a real file.
bool isHttpUrl(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// True for the server's "no image" placeholders, which it sends as if they
/// were real images: `…/loadingImages/loading.gif` (staff and category
/// images), `defaultImages/loading.gif` (missing subtitles) and
/// `defaultImages/not_available.jpg` (staff photos, answers 503).
bool isPlaceholderImage(String? url) {
  if (url == null) return false;
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.contains('loadingimages/') ||
      path.contains('defaultimages/') ||
      path.endsWith('/loading.gif') ||
      path == 'loading.gif';
}

/// An absolute http(s) image URL that isn't a placeholder, or `null`.
String? realImageUrl(String? url) {
  if (url == null) return null;
  final s = unescapeUrl(url);
  return isHttpUrl(s) && !isPlaceholderImage(s) ? s : null;
}

/// [seconds] as a [Duration], or `null` when it isn't a real length: not
/// finite, or so large that [Duration] would overflow (it counts in
/// microseconds, and a huge value would wrap round to a negative one).
Duration? durationFromSeconds(double? seconds) {
  if (seconds == null || !seconds.isFinite) return null;
  final ms = seconds * 1000;
  if (!ms.isFinite || ms.abs() > _maxDurationMs) return null;
  return Duration(milliseconds: ms.round());
}

/// About 285,000 years, well inside [Duration]'s range.
const _maxDurationMs = 9e15;

/// When a signed URL stops working, from its `Expires` query parameter
/// (seconds since the epoch). `null` when the URL isn't signed or the value
/// isn't a date [DateTime] can hold.
DateTime? signedUrlExpiry(String url) {
  final raw = Uri.tryParse(url)?.queryParameters['Expires'];
  final seconds = raw == null ? null : int.tryParse(raw.trim());
  if (seconds == null || seconds.abs() > _maxEpochSeconds) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// [DateTime]'s limit (±8.64e15 ms), in seconds.
const _maxEpochSeconds = 8640000000000;

/// An ID: non-blank and not "0" (the API uses 0 for "none").
String? readId(Object? value) {
  final s = readString(value);
  return (s == null || s == '0') ? null : s;
}
