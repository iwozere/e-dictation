import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dictations/domain/dictation.dart' show DictationLanguage;
import '../domain/quiz_attempt.dart';
import '../domain/quiz_card.dart';
import '../domain/quiz_deck.dart';
import '../domain/quiz_failure.dart';
import '../domain/quiz_practice_deck.dart';

final _log = Logger('quiz.QuizRepository');

const _deckWithCardsSelect =
    '*, quiz_cards(id, deck_id, position, '
    'quiz_card_options(id, card_id, side, text, is_correct, audio_url, audio_duration_ms))';

/// Handles all Supabase DB operations and Edge Function/RPC triggers for
/// quiz decks. Mirrors CardsRepository's shape and error-handling
/// conventions; see docs/cr-quiz-decks-timed-multiple-choice.md.
class QuizRepository {
  QuizRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------------------
  // Queries — teacher (owner access via direct RLS)
  // ---------------------------------------------------------------------------

  Future<(List<QuizDeck>?, QuizFailure?)> fetchDecks({
    required String ownerId,
    String? classId,
  }) async {
    try {
      var filterQuery = _client
          .from('quiz_decks')
          .select(_deckWithCardsSelect)
          .eq('owner_id', ownerId);

      if (classId != null) {
        filterQuery = filterQuery.eq('class_id', classId);
      }

      final rows =
          await filterQuery
                  .order('created_at', ascending: false)
                  .order('position', referencedTable: 'quiz_cards')
              as List<dynamic>;
      final decks = rows
          .map((r) => _deckFromNestedJson(r as Map<String, dynamic>))
          .toList();
      return (decks, null);
    } catch (e) {
      _log.severe('fetchDecks error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }

  Future<(QuizDeck?, QuizFailure?)> fetchById(String id) async {
    try {
      final row = await _client
          .from('quiz_decks')
          .select(_deckWithCardsSelect)
          .eq('id', id)
          .order('position', referencedTable: 'quiz_cards')
          .single();

      return (_deckFromNestedJson(row), null);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') return (null, const QuizDeckNotFound());
      return (null, NetworkQuizFailure(e.message));
    } catch (e) {
      _log.severe('fetchById error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }

  /// The nested Postgrest select doesn't produce the `options_a`/`options_b`
  /// shape [QuizCard.fromJson] expects (that's specific to
  /// `get_quiz_deck_by_share_code`'s hand-built json) — it groups
  /// `quiz_card_options` flatly under `side`, so cards are assembled here.
  QuizDeck _deckFromNestedJson(Map<String, dynamic> json) {
    final cardsJson = (json['quiz_cards'] as List<dynamic>?) ?? const [];
    final cards = cardsJson.map((c) {
      final cardMap = c as Map<String, dynamic>;
      final options =
          (cardMap['quiz_card_options'] as List<dynamic>?)
              ?.map((o) => o as Map<String, dynamic>)
              .toList() ??
          const [];
      return QuizCard(
        id: cardMap['id'] as String,
        deckId: cardMap['deck_id'] as String,
        position: cardMap['position'] as int,
        optionsA: options
            .where((o) => o['side'] == 'a')
            .map(QuizOption.fromJson)
            .toList(),
        optionsB: options
            .where((o) => o['side'] == 'b')
            .map(QuizOption.fromJson)
            .toList(),
      );
    }).toList()..sort((a, b) => a.position.compareTo(b.position));

    return QuizDeck.fromJson({...json, 'cards': null}).copyWith(cards: cards);
  }

  /// Fetches a single *ready* deck by [shareCode] (public / anonymous
  /// access) via `get_quiz_deck_by_share_code`.
  ///
  /// Called once with [direction] null for the pre-direction choice screen
  /// (title/card-count only, no card content), then again once the student
  /// has picked a direction — only then does the server know which side to
  /// reveal as the prompt and which to reduce to 3 hidden-answer options.
  /// See the CR doc's Security section for why this can't be decided
  /// client-side after a single direction-agnostic fetch.
  Future<(QuizPracticeDeck?, QuizFailure?)> fetchByShareCode(
    String shareCode, {
    QuizDirection? direction,
  }) async {
    try {
      final result = await _client.rpc(
        'get_quiz_deck_by_share_code',
        params: {
          'p_share_code': shareCode,
          if (direction != null) 'p_direction': direction.value,
        },
      );

      if (result == null) return (null, const QuizDeckNotFound());
      return (QuizPracticeDeck.fromJson(result as Map<String, dynamic>), null);
    } on PostgrestException catch (e) {
      if (e.code == 'P0002') return (null, const QuizDeckNotFound());
      _log.warning('fetchByShareCode error: %s', e.message);
      return (null, NetworkQuizFailure(e.message));
    } catch (e) {
      _log.severe('fetchByShareCode unexpected error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations — deck
  // ---------------------------------------------------------------------------

  Future<(QuizDeck?, QuizFailure?)> createDeck({
    required String ownerId,
    required String title,
    required DictationLanguage languageA,
    required DictationLanguage languageB,
    String? classId,
    int? sessionLength = 20,
    int timerInitialSecs = 10,
    int timerDecaySecs = 1,
    int timerDecayEveryNCards = 3,
    int timerFloorSecs = 3,
    bool livesEnabled = true,
    int livesCount = 3,
  }) async {
    try {
      final row = await _client
          .from('quiz_decks')
          .insert({
            'owner_id': ownerId,
            if (classId != null) 'class_id': classId,
            'title': title,
            'language_a': languageA.code,
            'language_b': languageB.code,
            'session_length': sessionLength,
            'timer_initial_secs': timerInitialSecs,
            'timer_decay_secs': timerDecaySecs,
            'timer_decay_every_n_cards': timerDecayEveryNCards,
            'timer_floor_secs': timerFloorSecs,
            'lives_enabled': livesEnabled,
            'lives_count': livesCount,
          })
          .select()
          .single();

      return (QuizDeck.fromJson(row), null);
    } catch (e) {
      _log.severe('createDeck error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }

  /// Updates the 4 session/timer settings a teacher can tune after creation
  /// (CR follow-up: "make configurable per quiz"). Deliberately narrow —
  /// only these columns, regardless of deck status — since none of them
  /// affect cards/options/audio, unlike everything else on this table.
  Future<QuizFailure?> updateSettings({
    required String deckId,
    required int? sessionLength,
    required int timerInitialSecs,
    required int timerDecayEveryNCards,
    required int timerFloorSecs,
  }) async {
    try {
      await _client
          .from('quiz_decks')
          .update({
            'session_length': sessionLength,
            'timer_initial_secs': timerInitialSecs,
            'timer_decay_every_n_cards': timerDecayEveryNCards,
            'timer_floor_secs': timerFloorSecs,
          })
          .eq('id', deckId);
      return null;
    } catch (e) {
      _log.severe('updateSettings error: %s', e);
      return UnknownQuizFailure(e.toString());
    }
  }

  Future<QuizFailure?> deleteDeck(String id) async {
    try {
      await _client.from('quiz_decks').delete().eq('id', id);
      return null;
    } catch (e) {
      _log.severe('deleteDeck error: %s', e);
      return UnknownQuizFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations — cards & options (draft review)
  // ---------------------------------------------------------------------------

  Future<(QuizCard?, QuizFailure?)> addCard({
    required String deckId,
    required int position,
  }) async {
    try {
      final row = await _client
          .from('quiz_cards')
          .insert({'deck_id': deckId, 'position': position})
          .select()
          .single();
      return (
        QuizCard(
          id: row['id'] as String,
          deckId: row['deck_id'] as String,
          position: row['position'] as int,
        ),
        null,
      );
    } catch (e) {
      _log.severe('addCard error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }

  Future<QuizFailure?> deleteCard(String id) async {
    try {
      await _client.from('quiz_cards').delete().eq('id', id);
      return null;
    } catch (e) {
      _log.severe('deleteCard error: %s', e);
      return UnknownQuizFailure(e.toString());
    }
  }

  Future<(QuizOption?, QuizFailure?)> addOption({
    required String cardId,
    required QuizSide side,
    required String text,
    bool isCorrect = false,
  }) async {
    try {
      final row = await _client
          .from('quiz_card_options')
          .insert({
            'card_id': cardId,
            'side': side.name,
            'text': text,
            'is_correct': isCorrect,
          })
          .select()
          .single();
      return (QuizOption.fromJson(row), null);
    } catch (e) {
      _log.severe('addOption error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }

  Future<QuizFailure?> updateOptionText(String id, String text) async {
    try {
      await _client
          .from('quiz_card_options')
          .update({'text': text})
          .eq('id', id);
      return null;
    } catch (e) {
      _log.severe('updateOptionText error: %s', e);
      return UnknownQuizFailure(e.toString());
    }
  }

  /// Marks [optionId] as the correct option for its (card, side), unsetting
  /// whichever option previously held that flag. Two sequential updates
  /// rather than one, so the DB's partial-unique-index invariant (at most
  /// one `is_correct` per card/side) is never violated mid-write.
  Future<QuizFailure?> setCorrectOption({
    required String cardId,
    required QuizSide side,
    required String optionId,
  }) async {
    try {
      await _client
          .from('quiz_card_options')
          .update({'is_correct': false})
          .eq('card_id', cardId)
          .eq('side', side.name)
          .eq('is_correct', true);
      await _client
          .from('quiz_card_options')
          .update({'is_correct': true})
          .eq('id', optionId);
      return null;
    } catch (e) {
      _log.severe('setCorrectOption error: %s', e);
      return UnknownQuizFailure(e.toString());
    }
  }

  Future<QuizFailure?> deleteOption(String id) async {
    try {
      await _client.from('quiz_card_options').delete().eq('id', id);
      return null;
    } catch (e) {
      _log.severe('deleteOption error: %s', e);
      return UnknownQuizFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Import from an existing card deck (no AI call — see CR doc §1)
  // ---------------------------------------------------------------------------

  Future<QuizFailure?> importFromCardDeck({
    required String quizDeckId,
    required String sourceCardDeckId,
  }) async {
    try {
      await _client.rpc(
        'import_quiz_deck_from_card_deck',
        params: {
          'p_quiz_deck_id': quizDeckId,
          'p_source_card_deck_id': sourceCardDeckId,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      _log.warning('importFromCardDeck failed: %s', e.message);
      return QuizImportFailed(e.message);
    } catch (e) {
      _log.warning('importFromCardDeck failed', e);
      return QuizImportFailed(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Edge Function trigger — audio generation
  // ---------------------------------------------------------------------------

  Future<QuizFailure?> generateAudio(String deckId) async {
    try {
      final response = await _client.functions.invoke(
        'generate_quiz_audio',
        body: {'deck_id': deckId},
      );
      if (response.status != 200) {
        final message = (response.data is Map)
            ? response.data['error'] as String?
            : null;
        return QuizAudioGenerationFailed(message);
      }
      return null;
    } catch (e) {
      _log.warning('generateAudio failed for $deckId', e);
      return QuizAudioGenerationFailed(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Student session RPCs
  // ---------------------------------------------------------------------------

  /// Calls `check_quiz_answer` — the only place correctness is determined.
  /// Returns `(isCorrect, correctOption)`.
  Future<(bool?, QuizOption?, QuizFailure?)> checkAnswer(
    String optionId,
  ) async {
    try {
      final result =
          await _client.rpc(
                'check_quiz_answer',
                params: {'p_option_id': optionId},
              )
              as Map<String, dynamic>;
      final isCorrect = result['is_correct'] as bool?;
      final correctOptionJson =
          result['correct_option'] as Map<String, dynamic>?;
      final correctOption = correctOptionJson != null
          ? QuizOption.fromJson(correctOptionJson)
          : null;
      return (isCorrect, correctOption, null);
    } on PostgrestException catch (e) {
      if (e.code == 'P0002') return (null, null, const QuizOptionNotFound());
      return (null, null, NetworkQuizFailure(e.message));
    } catch (e) {
      _log.severe('checkAnswer error: %s', e);
      return (null, null, UnknownQuizFailure(e.toString()));
    }
  }

  /// Submits a completed session via `submit_quiz_attempt`. Scoring is
  /// re-derived server-side; do not pass pre-computed correct/wrong counts.
  Future<(QuizAttempt?, QuizFailure?)> submitAttempt({
    required String deckId,
    required String direction,
    required List<Map<String, dynamic>> answers,
    String? studentName,
    String? studentPinHash,
    DateTime? startedAt,
  }) async {
    try {
      final result = await _client.rpc(
        'submit_quiz_attempt',
        params: {
          'p_deck_id': deckId,
          'p_direction': direction,
          'p_answers': answers,
          'p_student_name': studentName,
          'p_pin_hash': studentPinHash,
          if (startedAt != null)
            'p_started_at': startedAt.toUtc().toIso8601String(),
        },
      );
      return (QuizAttempt.fromJson(result as Map<String, dynamic>), null);
    } catch (e) {
      _log.severe('submitAttempt error: %s', e);
      return (null, QuizSubmitFailed(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Teacher results
  // ---------------------------------------------------------------------------

  Future<(List<QuizAttempt>?, QuizFailure?)> fetchAttempts(
    String deckId,
  ) async {
    try {
      final rows =
          await _client
                  .from('quiz_attempts')
                  .select()
                  .eq('deck_id', deckId)
                  .order('submitted_at', ascending: false)
              as List<dynamic>;
      return (
        rows
            .map((r) => QuizAttempt.fromJson(r as Map<String, dynamic>))
            .toList(),
        null,
      );
    } catch (e) {
      _log.severe('fetchAttempts error: %s', e);
      return (null, UnknownQuizFailure(e.toString()));
    }
  }
}
