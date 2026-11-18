/// Text the API sends in English and Arabic (`en_title` / `ar_title`).
class LocalizedText {
  const LocalizedText({this.en, this.ar});

  final String? en;
  final String? ar;

  bool get isEmpty => en == null && ar == null;

  /// The text for the UI language, falling back to the other language.
  String? resolve({required bool arabic}) => arabic ? (ar ?? en) : (en ?? ar);

  @override
  bool operator ==(Object other) =>
      other is LocalizedText && other.en == en && other.ar == ar;

  @override
  int get hashCode => Object.hash(en, ar);

  @override
  String toString() => 'LocalizedText(en: $en, ar: $ar)';
}
