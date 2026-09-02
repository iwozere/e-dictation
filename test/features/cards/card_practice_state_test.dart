import 'package:e_dictation/features/cards/domain/card_pair.dart';
import 'package:e_dictation/features/cards/domain/card_practice_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final card = const CardPair(
    id: 'c1',
    deckId: 'd1',
    position: 0,
    textA: 'Haus',
    textB: 'house',
    audioAUrl: 'https://example.com/a.mp3',
    audioBUrl: 'https://example.com/b.mp3',
  );

  group('CardPracticeState prompt/answer/audio resolution', () {
    test(
      'nativeToForeign with native=A shows A, expects B, plays B audio (foreign)',
      () {
        final state = CardPracticeState(cards: [card], nativeSide: CardSide.a);

        expect(state.promptText, 'Haus');
        expect(state.expectedAnswer, 'house');
        expect(state.promptAudioUrl, 'https://example.com/b.mp3');
      },
    );

    test(
      'foreignToNative with native=A shows B, expects A, still plays B audio (foreign)',
      () {
        final state = CardPracticeState(
          cards: [card],
          nativeSide: CardSide.a,
          mode: PracticeMode.foreignToNative,
        );

        expect(state.promptText, 'house');
        expect(state.expectedAnswer, 'Haus');
        // Audio always plays the foreign side, regardless of mode — see the
        // CR doc's mode table (docs/cr-card-decks-language-flashcards.md).
        expect(state.promptAudioUrl, 'https://example.com/b.mp3');
      },
    );

    test('flips consistently when native=B instead', () {
      final state = CardPracticeState(cards: [card], nativeSide: CardSide.b);

      expect(state.promptText, 'house');
      expect(state.expectedAnswer, 'Haus');
      expect(state.promptAudioUrl, 'https://example.com/a.mp3');
    });

    test('foreignToNative with native=B mirrors the A case', () {
      final state = CardPracticeState(
        cards: [card],
        nativeSide: CardSide.b,
        mode: PracticeMode.foreignToNative,
      );

      expect(state.promptText, 'Haus');
      expect(state.expectedAnswer, 'house');
      expect(state.promptAudioUrl, 'https://example.com/a.mp3');
    });
  });

  test('CardSide.opposite flips a to b and back', () {
    expect(CardSide.a.opposite, CardSide.b);
    expect(CardSide.b.opposite, CardSide.a);
  });
}
