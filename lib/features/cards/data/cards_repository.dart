import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dictations/domain/dictation.dart' show DictationLanguage;
import '../domain/card_deck.dart';
import '../domain/card_deck_failure.dart';
import '../domain/card_pair.dart';

final _log = Logger('cards.CardsRepository');

/// Handles all Supabase DB operations and Edge Function triggers for card
/// decks and their cards. Mirrors DictationsRepository's shape and error
/// handling conventions.
class CardsRepository {
  CardsRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Fetches all card decks owned by [ownerId], ordered newest-first.
  Future<(List<CardDeck>?, CardDeckFailure?)> fetchDecks({
    required String ownerId,
    String? classId,
  }) async {
    try {
      var filterQuery = _client
          .from('card_decks')
          .select(
            '*, cards(id, deck_id, position, text_a, text_b, '
            'audio_a_url, audio_a_duration_ms, audio_b_url, audio_b_duration_ms)',
          )
          .eq('owner_id', ownerId);

      if (classId != null) {
        filterQuery = filterQuery.eq('class_id', classId);
      }

      final rows =
          await filterQuery
                  .order('created_at', ascending: false)
                  .order('position', referencedTable: 'cards')
              as List<dynamic>;
      final decks = rows
          .map((r) => CardDeck.fromJson(r as Map<String, dynamic>))
          .toList();
      return (decks, null);
    } catch (e) {
      _log.severe('fetchDecks error: %s', e);
      return (null, UnknownCardDeckFailure(e.toString()));
    }
  }

  /// Fetches a single deck by its [id] (owner access, via direct RLS).
  Future<(CardDeck?, CardDeckFailure?)> fetchById(String id) async {
    try {
      final row = await _client
          .from('card_decks')
          .select(
            '*, cards(id, deck_id, position, text_a, text_b, '
            'audio_a_url, audio_a_duration_ms, audio_b_url, audio_b_duration_ms)',
          )
          .eq('id', id)
          .order('position', referencedTable: 'cards')
          .single();

      return (CardDeck.fromJson(row), null);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') return (null, const CardDeckNotFound());
      return (null, NetworkCardDeckFailure(e.message));
    } catch (e) {
      _log.severe('fetchById error: %s', e);
      return (null, UnknownCardDeckFailure(e.toString()));
    }
  }

  /// Fetches a single *ready* deck by its [shareCode] (public / anonymous
  /// access) via the `get_card_deck_by_share_code` RPC.
  Future<(CardDeck?, CardDeckFailure?)> fetchByShareCode(
    String shareCode,
  ) async {
    try {
      final result = await _client.rpc(
        'get_card_deck_by_share_code',
        params: {'p_share_code': shareCode},
      );

      if (result == null) return (null, const CardDeckNotFound());
      return (CardDeck.fromJson(result as Map<String, dynamic>), null);
    } on PostgrestException catch (e) {
      if (e.code == 'P0002') return (null, const CardDeckNotFound());
      _log.warning('fetchByShareCode error: %s', e.message);
      return (null, NetworkCardDeckFailure(e.message));
    } catch (e) {
      _log.severe('fetchByShareCode unexpected error: %s', e);
      return (null, UnknownCardDeckFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations — deck
  // ---------------------------------------------------------------------------

  /// Inserts a new (empty, `status='pending'`) card deck row. Call
  /// [parseDeck] next to populate it from a photo.
  Future<(CardDeck?, CardDeckFailure?)> createDeck({
    required String ownerId,
    required String title,
    required DictationLanguage languageA,
    required DictationLanguage languageB,
    String? classId,
  }) async {
    try {
      final row = await _client
          .from('card_decks')
          .insert({
            'owner_id': ownerId,
            if (classId != null) 'class_id': classId,
            'title': title,
            'language_a': languageA.code,
            'language_b': languageB.code,
          })
          .select()
          .single();

      return (CardDeck.fromJson(row), null);
    } catch (e) {
      _log.severe('createDeck error: %s', e);
      return (null, UnknownCardDeckFailure(e.toString()));
    }
  }

  Future<CardDeckFailure?> deleteDeck(String id) async {
    try {
      await _client.from('card_decks').delete().eq('id', id);
      return null;
    } catch (e) {
      _log.severe('deleteDeck error: %s', e);
      return UnknownCardDeckFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations — cards (draft review)
  // ---------------------------------------------------------------------------

  Future<CardDeckFailure?> updateCardPair({
    required String id,
    required String textA,
    required String textB,
  }) async {
    try {
      await _client
          .from('cards')
          .update({'text_a': textA, 'text_b': textB})
          .eq('id', id);
      return null;
    } catch (e) {
      _log.severe('updateCardPair error: %s', e);
      return UnknownCardDeckFailure(e.toString());
    }
  }

  Future<(CardPair?, CardDeckFailure?)> addCardPair({
    required String deckId,
    required int position,
    String textA = '',
    String textB = '',
  }) async {
    try {
      final row = await _client
          .from('cards')
          .insert({
            'deck_id': deckId,
            'position': position,
            'text_a': textA,
            'text_b': textB,
          })
          .select()
          .single();
      return (CardPair.fromJson(row), null);
    } catch (e) {
      _log.severe('addCardPair error: %s', e);
      return (null, UnknownCardDeckFailure(e.toString()));
    }
  }

  Future<CardDeckFailure?> deleteCardPair(String id) async {
    try {
      await _client.from('cards').delete().eq('id', id);
      return null;
    } catch (e) {
      _log.severe('deleteCardPair error: %s', e);
      return UnknownCardDeckFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Edge Function triggers
  // ---------------------------------------------------------------------------

  /// Calls the `parse_card_deck` Edge Function, which sends [imageBase64] to
  /// Claude and writes the extracted pairs as draft `cards` rows.
  /// Awaited (unlike dictations' fire-and-forget TTS trigger) so the review
  /// screen can react to the result immediately.
  Future<CardDeckFailure?> parseDeck({
    required String deckId,
    required String imageBase64,
    required String mimeType,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'parse_card_deck',
        body: {
          'deck_id': deckId,
          'image_base64': imageBase64,
          'mime_type': mimeType,
        },
      );
      if (response.status != 200) {
        final message = (response.data is Map)
            ? response.data['error'] as String?
            : null;
        return CardDeckParseFailed(message);
      }
      return null;
    } catch (e) {
      _log.warning('parseDeck failed for $deckId', e);
      return CardDeckParseFailed(e.toString());
    }
  }

  /// Calls the `generate_card_audio` Edge Function, which synthesizes TTS
  /// for every card and flips the deck to `status='ready'`.
  Future<CardDeckFailure?> generateAudio(String deckId) async {
    try {
      final response = await _client.functions.invoke(
        'generate_card_audio',
        body: {'deck_id': deckId},
      );
      if (response.status != 200) {
        final message = (response.data is Map)
            ? response.data['error'] as String?
            : null;
        return CardDeckAudioGenerationFailed(message);
      }
      return null;
    } catch (e) {
      _log.warning('generateAudio failed for $deckId', e);
      return CardDeckAudioGenerationFailed(e.toString());
    }
  }
}
