import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../dictations/domain/dictation.dart' show DictationLanguage;
import '../../domain/quiz_card.dart';
import '../../domain/quiz_deck.dart';
import '../providers/quiz_provider.dart';

/// Adapts to the deck's status:
///  - draft    → editable cards/options + "Save & generate audio"
///  - pending  → "generating audio" spinner, polls
///  - ready    → share link + read-only card list + "Edit" toggle + Results
///  - failed   → error message + retry
class QuizDeckDetailScreen extends ConsumerStatefulWidget {
  const QuizDeckDetailScreen({super.key, required this.deckId});
  final String deckId;

  @override
  ConsumerState<QuizDeckDetailScreen> createState() =>
      _QuizDeckDetailScreenState();
}

class _QuizDeckDetailScreenState extends ConsumerState<QuizDeckDetailScreen> {
  Timer? _pollTimer;
  List<String> _loadedOptionIds = const [];
  final Map<String, TextEditingController> _optionCtrls = {};
  final _titleCtrl = TextEditingController();
  DictationLanguage? _editLanguageA;
  DictationLanguage? _editLanguageB;
  String? _infoLoadedForDeckId;
  bool _editing = false;
  bool _busy = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final c in _optionCtrls.values) {
      c.dispose();
    }
    _titleCtrl.dispose();
    super.dispose();
  }

  /// Loads title/language into editable state once per deck id — like
  /// [_syncControllers], this deliberately does NOT re-run on every refetch
  /// so it doesn't clobber in-progress edits (e.g. after the settings
  /// dialog invalidates the provider).
  void _syncDeckInfo(QuizDeck deck) {
    if (_infoLoadedForDeckId == deck.id) return;
    _infoLoadedForDeckId = deck.id;
    _titleCtrl.text = deck.title;
    _editLanguageA = deck.languageA;
    _editLanguageB = deck.languageB;
  }

  void _syncControllers(List<QuizCard> cards) {
    final ids = [
      for (final c in cards) ...c.optionsA.map((o) => o.id),
      for (final c in cards) ...c.optionsB.map((o) => o.id),
    ];
    if (listEquals(ids, _loadedOptionIds)) return;
    _loadedOptionIds = ids;
    for (final c in _optionCtrls.values) {
      c.dispose();
    }
    _optionCtrls.clear();
    for (final card in cards) {
      for (final o in [...card.optionsA, ...card.optionsB]) {
        _optionCtrls[o.id] = TextEditingController(text: o.text);
      }
    }
  }

  void _updatePolling(QuizDeckStatus status) {
    final shouldPoll = status == QuizDeckStatus.pending;
    if (shouldPoll && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        ref.invalidate(quizDeckByIdProvider(widget.deckId));
      });
    } else if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _addCard(QuizDeck deck) async {
    final (_, failure) = await ref
        .read(quizRepositoryProvider)
        .addCard(deckId: deck.id, position: deck.cards.length);
    if (!mounted) return;
    if (failure != null) {
      _showError('Could not add a new card.');
      return;
    }
    ref.invalidate(quizDeckByIdProvider(widget.deckId));
  }

  Future<void> _deleteCard(QuizCard card) async {
    final failure = await ref.read(quizRepositoryProvider).deleteCard(card.id);
    if (!mounted) return;
    if (failure != null) {
      _showError('Could not delete that card.');
      return;
    }
    ref.invalidate(quizDeckByIdProvider(widget.deckId));
  }

  Future<void> _addOption(QuizCard card, QuizSide side) async {
    final existing = card.optionsFor(side);
    final (_, failure) = await ref
        .read(quizRepositoryProvider)
        .addOption(
          cardId: card.id,
          side: side,
          text: '',
          // The first option added to an empty side has nothing to compare
          // against yet, so it becomes the correct one by default.
          isCorrect: existing.isEmpty,
        );
    if (!mounted) return;
    if (failure != null) {
      _showError('Could not add that option.');
      return;
    }
    ref.invalidate(quizDeckByIdProvider(widget.deckId));
  }

  Future<void> _deleteOption(QuizOption option) async {
    final failure = await ref
        .read(quizRepositoryProvider)
        .deleteOption(option.id);
    if (!mounted) return;
    if (failure != null) {
      _showError('Could not delete that option.');
      return;
    }
    ref.invalidate(quizDeckByIdProvider(widget.deckId));
  }

  Future<void> _setCorrect(
    QuizCard card,
    QuizSide side,
    String optionId,
  ) async {
    final failure = await ref
        .read(quizRepositoryProvider)
        .setCorrectOption(cardId: card.id, side: side, optionId: optionId);
    if (!mounted) return;
    if (failure != null) {
      _showError('Could not update the correct answer.');
      return;
    }
    ref.invalidate(quizDeckByIdProvider(widget.deckId));
  }

  /// At least 3 options (1 correct + 2 wrong) per (card, side) — see the CR
  /// doc's Key decision #1. Returns a human-readable problem, or null if
  /// every card/side is ready for audio generation.
  String? _validate(QuizDeck deck) {
    if (deck.cards.isEmpty) return 'Add at least one card first.';
    for (final card in deck.cards) {
      for (final side in QuizSide.values) {
        final options = card.optionsFor(side);
        if (options.length < 3) {
          return 'Card ${card.position + 1}: each side needs at least 3 options (1 correct + 2 wrong).';
        }
        final correctCount = options.where((o) => o.isCorrect == true).length;
        if (correctCount != 1) {
          return 'Card ${card.position + 1}: pick exactly one correct option per side.';
        }
        if (options.any((o) => o.text.trim().isEmpty)) {
          return 'Card ${card.position + 1}: fill in every option before generating audio.';
        }
      }
    }
    return null;
  }

  Future<void> _saveAndGenerate(QuizDeck deck) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showError('Title is required.');
      return;
    }
    final languageA = _editLanguageA ?? deck.languageA;
    final languageB = _editLanguageB ?? deck.languageB;
    if (languageA == languageB) {
      _showError('Pick two different languages.');
      return;
    }
    final problem = _validate(deck);
    if (problem != null) {
      _showError(problem);
      return;
    }

    setState(() => _busy = true);

    if (title != deck.title ||
        languageA != deck.languageA ||
        languageB != deck.languageB) {
      await ref
          .read(quizDeckMutationProvider.notifier)
          .updateDeckInfo(
            deckId: deck.id,
            title: title,
            languageA: languageA,
            languageB: languageB,
          );
    }

    for (final card in deck.cards) {
      for (final option in [...card.optionsA, ...card.optionsB]) {
        final edited = _optionCtrls[option.id]?.text.trim() ?? option.text;
        if (edited != option.text) {
          await ref
              .read(quizRepositoryProvider)
              .updateOptionText(option.id, edited);
        }
      }
    }

    final failure = await ref
        .read(quizRepositoryProvider)
        .generateAudio(deck.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = false;
    });
    if (failure != null) {
      _showError('Could not generate audio. Try again.');
    }
    ref.invalidate(quizDeckByIdProvider(widget.deckId));
    ref.invalidate(teacherQuizDecksProvider);
  }

  void _copyLink(String shareCode) {
    Clipboard.setData(
      ClipboardData(text: '${AppConfig.appBaseUrl}/q/$shareCode'),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied!')));
  }

  Future<void> _openSettingsDialog(QuizDeck deck) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SettingsDialog(deck: deck),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings updated.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final deckAsync = ref.watch(quizDeckByIdProvider(widget.deckId));

    ref.listen(quizDeckByIdProvider(widget.deckId), (_, next) {
      next.whenData((d) => _updatePolling(d.status));
    });

    return deckAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Quiz deck')),
        body: ErrorView(
          message: 'Could not load this deck.',
          onRetry: () => ref.invalidate(quizDeckByIdProvider(widget.deckId)),
        ),
      ),
      data: (deck) {
        _syncControllers(deck.cards);
        _syncDeckInfo(deck);

        return Scaffold(
          appBar: AppBar(
            title: SelectionArea(child: Text(deck.title)),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Timer, lives & session settings',
                onPressed: () => _openSettingsDialog(deck),
              ),
              if (deck.status == QuizDeckStatus.ready) ...[
                IconButton(
                  icon: const Icon(Icons.bar_chart_outlined),
                  tooltip: 'Results',
                  onPressed: () =>
                      context.go('/teacher/quiz/${deck.id}/results'),
                ),
                if (deck.shareCode != null) ...[
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'Preview',
                    onPressed: () => context.go('/q/${deck.shareCode}'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Copy share link',
                    onPressed: () => _copyLink(deck.shareCode!),
                  ),
                ],
              ],
            ],
          ),
          body: switch (deck.status) {
            QuizDeckStatus.pending => const _ProcessingView(),
            QuizDeckStatus.failed => _FailedView(deck: deck),
            QuizDeckStatus.draft => _ReviewView(
              deck: deck,
              optionCtrls: _optionCtrls,
              titleCtrl: _titleCtrl,
              languageA: _editLanguageA ?? deck.languageA,
              languageB: _editLanguageB ?? deck.languageB,
              onLanguageAChanged: (v) => setState(() => _editLanguageA = v),
              onLanguageBChanged: (v) => setState(() => _editLanguageB = v),
              busy: _busy,
              onAddCard: () => _addCard(deck),
              onDeleteCard: _deleteCard,
              onAddOption: _addOption,
              onDeleteOption: _deleteOption,
              onSetCorrect: _setCorrect,
              onConfirm: () => _saveAndGenerate(deck),
            ),
            QuizDeckStatus.ready =>
              _editing
                  ? _ReviewView(
                      deck: deck,
                      optionCtrls: _optionCtrls,
                      titleCtrl: _titleCtrl,
                      languageA: _editLanguageA ?? deck.languageA,
                      languageB: _editLanguageB ?? deck.languageB,
                      onLanguageAChanged: (v) =>
                          setState(() => _editLanguageA = v),
                      onLanguageBChanged: (v) =>
                          setState(() => _editLanguageB = v),
                      busy: _busy,
                      onAddCard: () => _addCard(deck),
                      onDeleteCard: _deleteCard,
                      onAddOption: _addOption,
                      onDeleteOption: _deleteOption,
                      onSetCorrect: _setCorrect,
                      onConfirm: () => _saveAndGenerate(deck),
                    )
                  : _ReadyView(
                      deck: deck,
                      onCopyLink: () => _copyLink(deck.shareCode!),
                      onEdit: () => setState(() => _editing = true),
                    ),
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Generating audio for every option…'),
        ],
      ),
    ),
  );
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.deck});
  final QuizDeck deck;

  @override
  Widget build(BuildContext context) => ErrorView(
    message: deck.statusError ?? 'Something went wrong generating audio.',
  );
}

// ---------------------------------------------------------------------------
// Settings dialog — the 4 teacher-configurable timer/session values
// (CR follow-up: "make configurable per quiz"). Available at any deck
// status since none of these touch cards/options/audio.
// ---------------------------------------------------------------------------

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog({required this.deck});
  final QuizDeck deck;

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late final _sessionLengthCtrl = TextEditingController(
    text: '${widget.deck.sessionLength ?? 20}',
  );
  late final _timerInitialCtrl = TextEditingController(
    text: '${widget.deck.timerInitialSecs}',
  );
  late final _timerDecayEveryNCtrl = TextEditingController(
    text: '${widget.deck.timerDecayEveryNCards}',
  );
  late final _timerFloorCtrl = TextEditingController(
    text: '${widget.deck.timerFloorSecs}',
  );
  late final _livesCountCtrl = TextEditingController(
    text: '${widget.deck.livesCount}',
  );
  late bool _wholeDeckSession = widget.deck.sessionLength == null;
  late bool _livesEnabled = widget.deck.livesEnabled;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _sessionLengthCtrl.dispose();
    _timerInitialCtrl.dispose();
    _timerDecayEveryNCtrl.dispose();
    _timerFloorCtrl.dispose();
    _livesCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final timerInitialSecs = int.tryParse(_timerInitialCtrl.text) ?? 10;
    final timerFloorSecs = int.tryParse(_timerFloorCtrl.text) ?? 3;
    final timerDecayEveryNCards = int.tryParse(_timerDecayEveryNCtrl.text) ?? 3;
    final sessionLength = _wholeDeckSession
        ? null
        : int.tryParse(_sessionLengthCtrl.text) ?? 20;

    if (!_wholeDeckSession && (sessionLength == null || sessionLength <= 0)) {
      setState(() => _error = 'Cards per session must be at least 1.');
      return;
    }
    final problem = validateQuizTimerSettings(
      timerInitialSecs: timerInitialSecs,
      timerFloorSecs: timerFloorSecs,
      timerDecayEveryNCards: timerDecayEveryNCards,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final failure = await ref
        .read(quizDeckMutationProvider.notifier)
        .updateSettings(
          deckId: widget.deck.id,
          sessionLength: sessionLength,
          timerInitialSecs: timerInitialSecs,
          timerDecayEveryNCards: timerDecayEveryNCards,
          timerFloorSecs: timerFloorSecs,
          livesEnabled: _livesEnabled,
          livesCount: int.tryParse(_livesCountCtrl.text) ?? 3,
        );

    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _saving = false;
        _error = 'Could not save settings. Try again.';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Timer, lives & session settings'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sessionLengthCtrl,
                    enabled: !_wholeDeckSession,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Cards per session',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Whole deck'),
                    value: _wholeDeckSession,
                    onChanged: (v) =>
                        setState(() => _wholeDeckSession = v ?? false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timerInitialCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Starting time per card (seconds)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timerDecayEveryNCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cards between decreases',
                helperText: 'The timer shortens every N cards.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timerFloorCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Minimum time (seconds)',
                helperText: "Won't shorten past this floor.",
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lives'),
                    subtitle: const Text(
                      'End the session early after too many misses',
                    ),
                    value: _livesEnabled,
                    onChanged: (v) => setState(() => _livesEnabled = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _livesCountCtrl,
                    enabled: _livesEnabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Lives'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ready view — read-only summary
// ---------------------------------------------------------------------------

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.deck,
    required this.onCopyLink,
    required this.onEdit,
  });
  final QuizDeck deck;
  final VoidCallback onCopyLink;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (deck.shareCode != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Share code',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          deck.shareCode!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.primary),
                    tooltip: 'Copy link',
                    onPressed: onCopyLink,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${deck.languageA.label} / ${deck.languageB.label} · ${deck.cards.length} cards',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...deck.cards.map((c) {
            final correctA = c.correctOptionFor(QuizSide.a);
            final correctB = c.correctOptionFor(QuizSide.b);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 18,
              ),
              title: Text(
                '${correctA?.text ?? '?'}  →  ${correctB?.text ?? '?'}',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '${c.optionsA.length} · ${c.optionsB.length} options',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review view — editable cards/options
// ---------------------------------------------------------------------------

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.deck,
    required this.optionCtrls,
    required this.titleCtrl,
    required this.languageA,
    required this.languageB,
    required this.onLanguageAChanged,
    required this.onLanguageBChanged,
    required this.busy,
    required this.onAddCard,
    required this.onDeleteCard,
    required this.onAddOption,
    required this.onDeleteOption,
    required this.onSetCorrect,
    required this.onConfirm,
  });

  final QuizDeck deck;
  final Map<String, TextEditingController> optionCtrls;
  final TextEditingController titleCtrl;
  final DictationLanguage languageA;
  final DictationLanguage languageB;
  final ValueChanged<DictationLanguage?> onLanguageAChanged;
  final ValueChanged<DictationLanguage?> onLanguageBChanged;
  final bool busy;
  final VoidCallback onAddCard;
  final void Function(QuizCard card) onDeleteCard;
  final void Function(QuizCard card, QuizSide side) onAddOption;
  final void Function(QuizOption option) onDeleteOption;
  final void Function(QuizCard card, QuizSide side, String optionId)
  onSetCorrect;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<DictationLanguage>(
                      initialValue: languageA,
                      decoration: const InputDecoration(
                        labelText: 'Language A',
                      ),
                      items: DictationLanguage.values
                          .map(
                            (l) => DropdownMenuItem(
                              value: l,
                              child: Text(l.label),
                            ),
                          )
                          .toList(),
                      onChanged: onLanguageAChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<DictationLanguage>(
                      initialValue: languageB,
                      decoration: const InputDecoration(
                        labelText: 'Language B',
                      ),
                      items: DictationLanguage.values
                          .map(
                            (l) => DropdownMenuItem(
                              value: l,
                              child: Text(l.label),
                            ),
                          )
                          .toList(),
                      onChanged: onLanguageBChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Each side needs one correct answer plus 2 or more wrong '
                'variants — every one of them gets pronounced when clicked, '
                'so fill them all in before generating audio. Changing a '
                'language regenerates audio for every option on save.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: deck.cards.length,
            itemBuilder: (_, i) => _CardEditor(
              languageALabel: languageA.label,
              languageBLabel: languageB.label,
              card: deck.cards[i],
              optionCtrls: optionCtrls,
              onDeleteCard: onDeleteCard,
              onAddOption: onAddOption,
              onDeleteOption: onDeleteOption,
              onSetCorrect: onSetCorrect,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onAddCard,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add card'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: busy ? null : onConfirm,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.volume_up_outlined, size: 18),
                label: Text(busy ? 'Generating…' : 'Save & generate audio'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardEditor extends StatelessWidget {
  const _CardEditor({
    required this.languageALabel,
    required this.languageBLabel,
    required this.card,
    required this.optionCtrls,
    required this.onDeleteCard,
    required this.onAddOption,
    required this.onDeleteOption,
    required this.onSetCorrect,
  });

  final String languageALabel;
  final String languageBLabel;
  final QuizCard card;
  final Map<String, TextEditingController> optionCtrls;
  final void Function(QuizCard card) onDeleteCard;
  final void Function(QuizCard card, QuizSide side) onAddOption;
  final void Function(QuizOption option) onDeleteOption;
  final void Function(QuizCard card, QuizSide side, String optionId)
  onSetCorrect;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Card ${card.position + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.error,
                  ),
                  tooltip: 'Delete card',
                  onPressed: () => onDeleteCard(card),
                ),
              ],
            ),
            _SideEditor(
              label: languageALabel,
              card: card,
              side: QuizSide.a,
              optionCtrls: optionCtrls,
              onAddOption: onAddOption,
              onDeleteOption: onDeleteOption,
              onSetCorrect: onSetCorrect,
            ),
            const Divider(),
            _SideEditor(
              label: languageBLabel,
              card: card,
              side: QuizSide.b,
              optionCtrls: optionCtrls,
              onAddOption: onAddOption,
              onDeleteOption: onDeleteOption,
              onSetCorrect: onSetCorrect,
            ),
          ],
        ),
      ),
    );
  }
}

class _SideEditor extends StatelessWidget {
  const _SideEditor({
    required this.label,
    required this.card,
    required this.side,
    required this.optionCtrls,
    required this.onAddOption,
    required this.onDeleteOption,
    required this.onSetCorrect,
  });

  final String label;
  final QuizCard card;
  final QuizSide side;
  final Map<String, TextEditingController> optionCtrls;
  final void Function(QuizCard card, QuizSide side) onAddOption;
  final void Function(QuizOption option) onDeleteOption;
  final void Function(QuizCard card, QuizSide side, String optionId)
  onSetCorrect;

  @override
  Widget build(BuildContext context) {
    final options = card.optionsFor(side);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          ...options.map(
            (o) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Mark as correct answer',
                    icon: Icon(
                      o.isCorrect == true
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: o.isCorrect == true
                          ? AppColors.success
                          : Colors.grey,
                    ),
                    onPressed: () => onSetCorrect(card, side, o.id),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: optionCtrls[o.id],
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: o.isCorrect == true
                            ? 'Correct answer'
                            : 'Wrong option',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.error,
                    ),
                    tooltip: 'Delete option',
                    onPressed: () => onDeleteOption(o),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 40),
            child: TextButton.icon(
              onPressed: () => onAddOption(card, side),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add option'),
            ),
          ),
        ],
      ),
    );
  }
}
