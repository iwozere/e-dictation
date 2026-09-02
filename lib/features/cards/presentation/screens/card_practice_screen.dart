import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/scoring/scoring.dart' show ScoringMode;
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/card_deck.dart';
import '../../domain/card_pair.dart';
import '../../domain/card_practice_state.dart';
import '../providers/card_practice_notifier.dart';
import '../providers/cards_provider.dart';

/// Student flashcard practice, opened via share link (`/c/:code`).
///
/// The student first picks which of the deck's two languages is their own
/// ("native") — persisted locally per deck so returning students skip the
/// prompt — then practices with a free choice of direction (see
/// docs/cr-card-decks-language-flashcards.md).
class CardPracticeScreen extends ConsumerStatefulWidget {
  const CardPracticeScreen({super.key, required this.shareCode});
  final String shareCode;

  @override
  ConsumerState<CardPracticeScreen> createState() => _CardPracticeScreenState();
}

class _CardPracticeScreenState extends ConsumerState<CardPracticeScreen> {
  bool _signingIn = false;
  String? _loadedDeckId;
  CardSide? _nativeSide;
  bool _prefsLoaded = false;
  final _answerCtrl = TextEditingController();

  String get _prefsKey => 'card_native_side_${widget.shareCode}';

  @override
  void initState() {
    super.initState();
    _loadNativeSidePref();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNativeSidePref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final stored = prefs.getString(_prefsKey);
    setState(() {
      _nativeSide = stored == 'b'
          ? CardSide.b
          : (stored == 'a' ? CardSide.a : null);
      _prefsLoaded = true;
    });
  }

  Future<void> _chooseNativeSide(CardSide side) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, side == CardSide.a ? 'a' : 'b');
    if (!mounted) return;
    setState(() => _nativeSide = side);
  }

  Future<void> _ensureAnonymousSession() async {
    if (_signingIn) return;
    _signingIn = true;
    await ref.read(authRepositoryProvider).signInAnonymously();
    _signingIn = false;
  }

  void _submit(CardPracticeState practice) {
    if (practice.lastAnswerCorrect != null) {
      // Already graded this card — the button now advances.
      _answerCtrl.clear();
      ref.read(cardPracticeNotifierProvider.notifier).next();
      return;
    }
    final deck = _currentDeck;
    ref
        .read(cardPracticeNotifierProvider.notifier)
        .submitAnswer(
          _answerCtrl.text,
          mode: deck?.scoringMode ?? ScoringMode.lenient,
        );
  }

  CardDeck? _currentDeck;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(authStateProvider);

    ref.listen<CardPracticeState>(cardPracticeNotifierProvider, (prev, next) {
      if (prev == null) return;
      if (prev.currentIndex != next.currentIndex) {
        _answerCtrl.clear();
      }
    });

    if (userAsync.isLoading || !_prefsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (userAsync.valueOrNull == null) {
      _ensureAnonymousSession();
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final deckAsync = ref.watch(cardDeckByShareCodeProvider(widget.shareCode));

    return deckAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Card deck')),
        body: const ErrorView(
          message: 'Deck not found. Check your share code.',
        ),
      ),
      data: (deck) {
        _currentDeck = deck;

        if (_nativeSide == null) {
          return _LanguageChoicePanel(deck: deck, onChoose: _chooseNativeSide);
        }

        if (deck.cards.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(deck.title)),
            body: const ErrorView(message: 'This deck has no cards yet.'),
          );
        }

        if (_loadedDeckId != deck.id) {
          _loadedDeckId = deck.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(cardPracticeNotifierProvider.notifier)
                .load(deck.cards, nativeSide: _nativeSide!);
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final practice = ref.watch(cardPracticeNotifierProvider);

        return Scaffold(
          appBar: AppBar(
            title: Text(deck.title),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ModeToggle(
                  deck: deck,
                  nativeSide: _nativeSide!,
                  mode: practice.mode,
                ),
              ),
            ),
          ),
          body: practice.completed
              ? _SummaryView(
                  correct: practice.correctCount,
                  total: practice.answeredCount,
                  onRestart: () => ref
                      .read(cardPracticeNotifierProvider.notifier)
                      .load(deck.cards, nativeSide: _nativeSide!),
                )
              : _PracticeBody(
                  deck: deck,
                  practice: practice,
                  answerCtrl: _answerCtrl,
                  onSubmit: () => _submit(practice),
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Language choice panel
// ---------------------------------------------------------------------------

class _LanguageChoicePanel extends StatelessWidget {
  const _LanguageChoicePanel({required this.deck, required this.onChoose});
  final CardDeck deck;
  final void Function(CardSide side) onChoose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(deck.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Which language do you already know?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '${deck.cards.length} pairs · ${deck.languageA.label} / ${deck.languageB.label}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () => onChoose(CardSide.a),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    deck.languageA.label,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => onChoose(CardSide.b),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    deck.languageB.label,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode toggle
// ---------------------------------------------------------------------------

class _ModeToggle extends ConsumerWidget {
  const _ModeToggle({
    required this.deck,
    required this.nativeSide,
    required this.mode,
  });
  final CardDeck deck;
  final CardSide nativeSide;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nativeLabel = deck.languageA.label == deck.languageB.label
        ? deck.languageA.label
        : (nativeSide == CardSide.a
              ? deck.languageA.label
              : deck.languageB.label);
    final foreignLabel = nativeSide == CardSide.a
        ? deck.languageB.label
        : deck.languageA.label;

    return SegmentedButton<PracticeMode>(
      segments: [
        ButtonSegment(
          value: PracticeMode.nativeToForeign,
          label: Text('$nativeLabel → $foreignLabel'),
        ),
        ButtonSegment(
          value: PracticeMode.foreignToNative,
          label: Text('$foreignLabel → $nativeLabel'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) => ref
          .read(cardPracticeNotifierProvider.notifier)
          .setMode(selected.first),
    );
  }
}

// ---------------------------------------------------------------------------
// Practice body
// ---------------------------------------------------------------------------

class _PracticeBody extends ConsumerWidget {
  const _PracticeBody({
    required this.deck,
    required this.practice,
    required this.answerCtrl,
    required this.onSubmit,
  });

  final CardDeck deck;
  final CardPracticeState practice;
  final TextEditingController answerCtrl;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graded = practice.lastAnswerCorrect != null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Card ${practice.currentIndex + 1} of ${practice.cards.length}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    practice.promptText ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  IconButton.filled(
                    iconSize: 32,
                    onPressed: () => ref
                        .read(cardPracticeNotifierProvider.notifier)
                        .playPrompt(),
                    icon: practice.audioStatus == PracticeAudioStatus.loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.volume_up),
                  ),
                ],
              ),
            ),
          ),
          if (graded)
            _FeedbackBanner(
              correct: practice.lastAnswerCorrect!,
              expected: practice.expectedAnswer ?? '',
            ),
          const SizedBox(height: 12),
          TextField(
            controller: answerCtrl,
            enabled: !graded,
            decoration: const InputDecoration(
              hintText: 'Type your answer…',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(graded ? 'Next →' : 'Check'),
          ),
        ],
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.correct, required this.expected});
  final bool correct;
  final String expected;

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            correct ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              correct ? 'Correct!' : 'Not quite — correct answer: $expected',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

class _SummaryView extends StatelessWidget {
  const _SummaryView({
    required this.correct,
    required this.total,
    required this.onRestart,
  });
  final int correct;
  final int total;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            size: 56,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '$correct / $total correct',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh),
            label: const Text('Practice again'),
          ),
        ],
      ),
    );
  }
}
