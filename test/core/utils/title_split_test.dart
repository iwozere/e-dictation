import 'package:flutter_test/flutter_test.dart';

import 'package:e_dictation/core/utils/title_split.dart';

void main() {
  group('splitLeadingTitle', () {
    test('splits a short heading from the body', () {
      final split = splitLeadingTitle('Der Herbst\nDie Blätter fallen.');
      expect(split, isNotNull);
      expect(split!.title, 'Der Herbst');
      expect(split.body, 'Die Blätter fallen.');
    });

    test('skips leading blank lines before the title', () {
      final split = splitLeadingTitle('\n  \nDer Herbst\nDie Blätter fallen.');
      expect(split, isNotNull);
      expect(split!.title, 'Der Herbst');
      expect(split.body, 'Die Blätter fallen.');
    });

    test('joins multi-line bodies unchanged', () {
      final split = splitLeadingTitle('Titel\nErster Satz.\nZweiter Satz.');
      expect(split!.body, 'Erster Satz.\nZweiter Satz.');
    });

    test('returns null for a single line', () {
      expect(splitLeadingTitle('Nur eine Zeile ohne Text danach'), isNull);
    });

    test('returns null for empty input', () {
      expect(splitLeadingTitle(''), isNull);
      expect(splitLeadingTitle('\n\n'), isNull);
    });

    test('returns null when the first line ends like a sentence', () {
      expect(
        splitLeadingTitle('Die Sonne scheint hell.\nEs ist warm.'),
        isNull,
      );
    });

    test('accepts a sentence-like first line separated by a blank line', () {
      final split = splitLeadingTitle('Der Herbst.\n\nDie Blätter fallen.');
      expect(split, isNotNull);
      expect(split!.title, 'Der Herbst.');
      expect(split.body, 'Die Blätter fallen.');
    });

    test('returns null when the first line is too long', () {
      final longLine = 'a' * 81;
      expect(splitLeadingTitle('$longLine\nBody text.'), isNull);
    });

    test('returns null when the first line has too many words', () {
      final manyWords = List.filled(13, 'Wort').join(' ');
      expect(splitLeadingTitle('$manyWords\nBody text.'), isNull);
    });
  });
}
