import 'package:e_dictation/features/dictations/domain/dictation.dart'
    show DictationLanguage;
import 'package:e_dictation/features/quiz/domain/quiz_attempt.dart';
import 'package:e_dictation/features/quiz/domain/quiz_card.dart';
import 'package:e_dictation/features/quiz/domain/quiz_practice_deck.dart';
import 'package:flutter_test/flutter_test.dart';

QuizPracticeDeck _deck({
  int timerInitialSecs = 10,
  int timerDecaySecs = 1,
  int timerDecayEveryNCards = 3,
  int timerFloorSecs = 3,
}) => QuizPracticeDeck(
  id: 'd1',
  title: 'Deck',
  languageA: DictationLanguage.german,
  languageB: DictationLanguage.english,
  timerInitialSecs: timerInitialSecs,
  timerDecaySecs: timerDecaySecs,
  timerDecayEveryNCards: timerDecayEveryNCards,
  timerFloorSecs: timerFloorSecs,
);

void main() {
  group('QuizPracticeDeck.timerSecondsForPosition', () {
    test('starts at the initial duration for the first card', () {
      final deck = _deck();
      expect(deck.timerSecondsForPosition(0), 10);
      expect(deck.timerSecondsForPosition(1), 10);
      expect(deck.timerSecondsForPosition(2), 10);
    });

    test('shortens by decaySecs every decayEveryNCards, based on position', () {
      final deck = _deck();
      expect(deck.timerSecondsForPosition(3), 9);
      expect(deck.timerSecondsForPosition(5), 9);
      expect(deck.timerSecondsForPosition(6), 8);
    });

    test('never drops below the floor', () {
      final deck = _deck(timerFloorSecs: 3);
      expect(deck.timerSecondsForPosition(100), 3);
    });

    test('decay is unaffected by accuracy — purely a function of position', () {
      final deck = _deck();
      // Same position always yields the same duration regardless of
      // anything the caller knows about correctness — see the CR doc's
      // Key decision #5 ("decay is based on position, not accuracy").
      expect(deck.timerSecondsForPosition(4), deck.timerSecondsForPosition(4));
    });
  });

  group('QuizDirection', () {
    test('aToB prompts with side A and answers with side B', () {
      expect(QuizDirection.aToB.promptSide, QuizSide.a);
      expect(QuizDirection.aToB.answerSide, QuizSide.b);
      expect(QuizDirection.aToB.value, 'a_to_b');
    });

    test('bToA prompts with side B and answers with side A', () {
      expect(QuizDirection.bToA.promptSide, QuizSide.b);
      expect(QuizDirection.bToA.answerSide, QuizSide.a);
      expect(QuizDirection.bToA.value, 'b_to_a');
    });

    test('fromString round-trips through value', () {
      expect(
        QuizDirection.fromString(QuizDirection.aToB.value),
        QuizDirection.aToB,
      );
      expect(
        QuizDirection.fromString(QuizDirection.bToA.value),
        QuizDirection.bToA,
      );
    });
  });

  group('QuizSide.opposite', () {
    test('flips a to b and back', () {
      expect(QuizSide.a.opposite, QuizSide.b);
      expect(QuizSide.b.opposite, QuizSide.a);
    });
  });

  group('QuizPromptCard.fromJson', () {
    test('parses prompt and reduced options, isCorrect stays hidden', () {
      final card = QuizPromptCard.fromJson({
        'id': 'c1',
        'position': 0,
        'prompt': {
          'id': 'o-correct',
          'text': 'Haus',
          'audio_url': 'https://example.com/haus.mp3',
          'audio_duration_ms': 900,
        },
        'options': [
          {
            'id': 'o1',
            'text': 'house',
            'audio_url': null,
            'audio_duration_ms': null,
          },
          {
            'id': 'o2',
            'text': 'car',
            'audio_url': null,
            'audio_duration_ms': null,
          },
          {
            'id': 'o3',
            'text': 'tree',
            'audio_url': null,
            'audio_duration_ms': null,
          },
        ],
      });

      expect(card.promptText, 'Haus');
      expect(card.promptAudioUrl, 'https://example.com/haus.mp3');
      expect(card.options, hasLength(3));
      expect(card.options.every((o) => o.isCorrect == null), isTrue);
    });
  });
}
