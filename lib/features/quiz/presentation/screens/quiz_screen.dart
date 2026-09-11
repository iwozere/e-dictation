import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/page_title.dart';
import '../../../../core/utils/pin_hash.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/quiz_attempt.dart';
import '../../domain/quiz_card.dart' show QuizOption;
import '../../domain/quiz_practice_deck.dart';
import '../../domain/quiz_session_state.dart';
import '../providers/quiz_provider.dart';
import '../providers/quiz_session_notifier.dart';

/// Student quiz practice, opened via share link (`/q/:code`).
///
/// Order of screens: identity (name/PIN, reused pattern from the dictation
/// player) → direction choice (locked for the session, CR doc's Key
/// decision #3) → the timed quiz itself → summary. Direction is chosen
/// *before* the content-bearing fetch, not after — see
/// `QuizRepository.fetchByShareCode` for why.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, required this.shareCode});
  final String shareCode;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  bool _signingIn = false;
  bool _identityDone = false;
  String? _studentName;
  String? _studentPinHash;
  QuizDirection? _direction;

  Future<void> _ensureAnonymousSession() async {
    if (_signingIn) return;
    _signingIn = true;
    await ref.read(authRepositoryProvider).signInAnonymously();
    _signingIn = false;
  }

  void _confirmIdentity(String? name, String? pinHash) {
    setState(() {
      _studentName = name;
      _studentPinHash = pinHash;
      _identityDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    setPageTitle(_studentName ?? 'Student');
    final userAsync = ref.watch(authStateProvider);

    if (userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (userAsync.valueOrNull == null) {
      _ensureAnonymousSession();
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final previewAsync = ref.watch(
      quizPracticeDeckProvider((widget.shareCode, null)),
    );

    return previewAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: const ErrorView(
          message: 'Quiz not found. Check your share code.',
        ),
      ),
      data: (preview) {
        if (!_identityDone) {
          return _IdentityPanel(
            title: preview.title,
            cardCount: preview.cardCount,
            onConfirm: _confirmIdentity,
          );
        }

        if (preview.cardCount == 0) {
          return Scaffold(
            appBar: AppBar(title: Text(preview.title)),
            body: const ErrorView(message: 'This quiz has no cards yet.'),
          );
        }

        if (_direction == null) {
          return _DirectionChoicePanel(
            deck: preview,
            onChoose: (d) => setState(() => _direction = d),
          );
        }

        return _QuizSession(
          shareCode: widget.shareCode,
          direction: _direction!,
          studentName: _studentName,
          studentPinHash: _studentPinHash,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Identity panel — same shape/copy as the dictation player's, reused
// pattern rather than a shared widget (see docs/cr-student-identification-
// results.md); kept local since the two features aren't otherwise coupled.
// ---------------------------------------------------------------------------

class _IdentityPanel extends StatefulWidget {
  const _IdentityPanel({
    required this.title,
    required this.cardCount,
    required this.onConfirm,
  });

  final String title;
  final int cardCount;
  final void Function(String? name, String? pinHash) onConfirm;

  @override
  State<_IdentityPanel> createState() => _IdentityPanelState();
}

class _IdentityPanelState extends State<_IdentityPanel> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    widget.onConfirm(
      name.isEmpty ? null : name,
      pin.isEmpty ? null : hashPin(pin),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                  'Before you start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your name so your teacher can see your results. '
                  'Add a PIN to protect your identity.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.bolt_outlined,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.cardCount} cards',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Your name (optional)',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'PIN (optional, 4 digits)',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _start(),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _start,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Start'),
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
// Direction choice — locked for the whole session once picked.
// ---------------------------------------------------------------------------

class _DirectionChoicePanel extends StatelessWidget {
  const _DirectionChoicePanel({required this.deck, required this.onChoose});
  final QuizPracticeDeck deck;
  final void Function(QuizDirection direction) onChoose;

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
                  'Which direction?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '${deck.cardCount} cards · this stays fixed for the whole session.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () => onChoose(QuizDirection.aToB),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    '${deck.languageA.label} → ${deck.languageB.label}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => onChoose(QuizDirection.bToA),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    '${deck.languageB.label} → ${deck.languageA.label}',
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
// Quiz session — fetches the direction-aware deck, loads the notifier once,
// then renders the running session or its summary.
// ---------------------------------------------------------------------------

class _QuizSession extends ConsumerStatefulWidget {
  const _QuizSession({
    required this.shareCode,
    required this.direction,
    required this.studentName,
    required this.studentPinHash,
  });

  final String shareCode;
  final QuizDirection direction;
  final String? studentName;
  final String? studentPinHash;

  @override
  ConsumerState<_QuizSession> createState() => _QuizSessionState();
}

class _QuizSessionState extends ConsumerState<_QuizSession> {
  // Lives on the State, not the (immutable) widget: a Riverpod-triggered
  // rebuild of this widget reuses the same State object but does NOT hand
  // it a new widget config, so a guard stored on the widget itself would
  // never observe its own update and load() would fire every rebuild —
  // see CardPracticeScreen's `_loadedDeckId` for the same pattern.
  String? _loadedSessionKey;

  @override
  Widget build(BuildContext context) {
    final deckAsync = ref.watch(
      quizPracticeDeckProvider((widget.shareCode, widget.direction)),
    );

    return deckAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => const Scaffold(
        body: ErrorView(message: 'Could not load the quiz. Try again.'),
      ),
      data: (deck) {
        // Watched unconditionally before the early return below, same
        // reason as CardPracticeScreen: this widget must already be
        // subscribed by the time the post-frame callback calls load().
        final session = ref.watch(quizSessionNotifierProvider);

        final sessionKey = widget.direction.value;
        if (_loadedSessionKey != sessionKey) {
          _loadedSessionKey = sessionKey;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(quizSessionNotifierProvider.notifier)
                .load(
                  deck: deck,
                  direction: widget.direction,
                  studentName: widget.studentName,
                  studentPinHash: widget.studentPinHash,
                );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(deck.title)),
          body: session.completed
              ? _SummaryView(
                  session: session,
                  onRestart: () =>
                      ref.read(quizSessionNotifierProvider.notifier).restart(),
                )
              : _QuizBody(
                  deck: deck,
                  session: session,
                  onSelect: (id) => ref
                      .read(quizSessionNotifierProvider.notifier)
                      .selectOption(id),
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quiz body — header (progress/streak/lives/timer), prompt, 3 options.
// ---------------------------------------------------------------------------

class _QuizBody extends StatelessWidget {
  const _QuizBody({
    required this.deck,
    required this.session,
    required this.onSelect,
  });

  final QuizPracticeDeck deck;
  final QuizSessionState session;
  final void Function(String optionId) onSelect;

  @override
  Widget build(BuildContext context) {
    final card = session.currentCard;
    if (card == null) return const SizedBox.shrink();

    final maxSecs = deck.timerSecondsForPosition(session.currentIndex);
    final timerFraction = maxSecs == 0
        ? 0.0
        : session.secondsRemaining / maxSecs;
    final timerLow = session.secondsRemaining <= 3;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Card ${session.currentIndex + 1} of ${session.sessionCards.length}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const Spacer(),
              if (session.streak >= 2) ...[
                const Text('🔥', style: TextStyle(fontSize: 14)),
                Text(
                  ' ×${session.streak}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (deck.livesEnabled)
                Row(
                  children: List.generate(
                    deck.livesCount,
                    (i) => Icon(
                      i < (session.livesRemaining ?? 0)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: AppColors.error,
                      size: 15,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: timerFraction.clamp(0.0, 1.0),
                    minHeight: 6,
                    color: timerLow ? AppColors.error : AppColors.primary,
                    backgroundColor: Colors.grey[200],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${session.secondsRemaining}s',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: timerLow ? AppColors.error : null,
                ),
              ),
            ],
          ),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              session.errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.promptText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PromptAudioButton(url: card.promptAudioUrl),
                ],
              ),
            ),
          ),
          if (session.feedback != null)
            _FeedbackBanner(feedback: session.feedback!),
          const SizedBox(height: 12),
          ...session.currentOptions.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionButton(
                option: o,
                feedback: session.feedback,
                onTap: () => onSelect(o.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptAudioButton extends StatefulWidget {
  const _PromptAudioButton({required this.url});
  final String? url;

  @override
  State<_PromptAudioButton> createState() => _PromptAudioButtonState();
}

class _PromptAudioButtonState extends State<_PromptAudioButton> {
  final _player = AudioPlayer();
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final url = widget.url;
    if (url == null || url.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      // Non-fatal — the prompt text is still shown even if audio fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      iconSize: 28,
      onPressed: _play,
      icon: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.volume_up),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.option,
    required this.feedback,
    required this.onTap,
  });

  final QuizOption option;
  final QuizFeedback? feedback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color? background;
    Color? foreground;
    if (feedback != null) {
      if (option.id == feedback!.correctOptionId) {
        background = AppColors.success;
        foreground = Colors.white;
      } else if (option.id == feedback!.selectedOptionId) {
        background = AppColors.error;
        foreground = Colors.white;
      }
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: feedback == null ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          disabledForegroundColor: foreground,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(option.text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.feedback});
  final QuizFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final color = feedback.correct ? AppColors.success : AppColors.error;
    final message = feedback.correct
        ? 'Correct!'
        : (feedback.selectedOptionId == null
              ? "Time's up — it's ${feedback.correctText ?? '…'}"
              : 'Not quite — it\'s ${feedback.correctText ?? '…'}');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            feedback.correct ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
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
  const _SummaryView({required this.session, required this.onRestart});
  final QuizSessionState session;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final total = session.totalCount;
    final accuracy = total == 0
        ? 0
        : ((session.correctCount / total) * 100).round();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            session.endedReason == QuizEndedReason.outOfLives
                ? Icons.heart_broken_outlined
                : Icons.emoji_events_outlined,
            size: 56,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          if (session.endedReason == QuizEndedReason.outOfLives)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Out of lives!',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          Text(
            '${session.correctCount} / $total correct  ·  $accuracy%',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Best streak: 🔥 ×${session.bestStreak}',
            style: TextStyle(color: Colors.grey[600]),
          ),
          if (session.submitting) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ] else ...[
            if (session.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  session.errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.refresh),
              label: const Text('Practice again'),
            ),
          ],
        ],
      ),
    );
  }
}
