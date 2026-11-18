import 'package:cinemakom/core/json/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readString trims, stringifies numbers, rejects blanks and "null"', () {
    expect(readString('  x '), 'x');
    expect(readString(12), '12');
    expect(readString(''), isNull);
    expect(readString('null'), isNull);
    expect(readString('NULL'), isNull);
    expect(readString(const {}), isNull);
  });

  test('parseIntLoose handles ints, doubles and messy strings', () {
    expect(parseIntLoose(3), 3);
    expect(parseIntLoose(3.6), 4);
    expect(parseIntLoose('12'), 12);
    expect(parseIntLoose('12.0'), 12);
    expect(parseIntLoose('S02'), 2);
    expect(parseIntLoose('abc'), isNull);
    expect(parseIntLoose(null), isNull);
  });

  test('parseDoubleLoose handles "7.5/10"', () {
    expect(parseDoubleLoose('7.5'), 7.5);
    expect(parseDoubleLoose('7.5/10'), 7.5);
    expect(parseDoubleLoose(8), 8.0);
    expect(parseDoubleLoose('n/a'), isNull);
  });

  test('parseBoolLoose', () {
    expect(parseBoolLoose('true'), isTrue);
    expect(parseBoolLoose('0'), isFalse);
    expect(parseBoolLoose(1), isTrue);
    expect(parseBoolLoose('maybe'), isNull);
  });

  test(r'unescapeUrl and isHttpUrl', () {
    expect(unescapeUrl(r'https:\/\/a.com\/x.jpg'), 'https://a.com/x.jpg');
    expect(isHttpUrl('https://a.com/x'), isTrue);
    expect(isHttpUrl('defaultImages/loading.gif'), isFalse);
    expect(isHttpUrl(null), isFalse);
  });

  test('readId treats "0" as no ID', () {
    expect(readId('0'), isNull);
    expect(readId(4328), '4328');
  });
}
