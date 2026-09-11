import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../cards/presentation/providers/cards_provider.dart'
    show teacherCardDecksProvider;
import '../../../classes/presentation/providers/classes_provider.dart';
import '../../../dictations/domain/dictation.dart' show DictationLanguage;
import '../providers/quiz_provider.dart';

enum _CreationMethod { blank, fromCardDeck }

/// Either starts a blank quiz deck (cards typed by hand on the next screen)
/// or imports word pairs from one of the teacher's existing card decks,
/// auto-filling distractors — see the CR doc's Key decision #1.
class CreateQuizDeckScreen extends ConsumerStatefulWidget {
  const CreateQuizDeckScreen({super.key});

  @override
  ConsumerState<CreateQuizDeckScreen> createState() =>
      _CreateQuizDeckScreenState();
}

class _CreateQuizDeckScreenState extends ConsumerState<CreateQuizDeckScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _sessionLengthCtrl = TextEditingController(text: '20');
  final _timerInitialCtrl = TextEditingController(text: '10');
  final _livesCountCtrl = TextEditingController(text: '3');

  DictationLanguage _languageA = DictationLanguage.german;
  DictationLanguage _languageB = DictationLanguage.english;
  String? _classId;
  _CreationMethod _method = _CreationMethod.blank;
  String? _sourceCardDeckId;
  bool _wholeDeckSession = false;
  bool _livesEnabled = true;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _sessionLengthCtrl.dispose();
    _timerInitialCtrl.dispose();
    _livesCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_languageA == _languageB) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick two different languages.')),
      );
      return;
    }
    if (_method == _CreationMethod.fromCardDeck && _sourceCardDeckId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a card deck to import from.')),
      );
      return;
    }

    setState(() => _saving = true);

    final (deck, createFailure) = await ref
        .read(quizDeckMutationProvider.notifier)
        .create(
          title: _titleCtrl.text.trim(),
          languageA: _languageA,
          languageB: _languageB,
          classId: _classId,
          sessionLength: _wholeDeckSession
              ? null
              : int.tryParse(_sessionLengthCtrl.text) ?? 20,
          timerInitialSecs: int.tryParse(_timerInitialCtrl.text) ?? 10,
          livesEnabled: _livesEnabled,
          livesCount: int.tryParse(_livesCountCtrl.text) ?? 3,
        );

    if (createFailure != null || deck == null) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create deck: ${createFailure.runtimeType}'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_method == _CreationMethod.fromCardDeck) {
      final importFailure = await ref
          .read(quizRepositoryProvider)
          .importFromCardDeck(
            quizDeckId: deck.id,
            sourceCardDeckId: _sourceCardDeckId!,
          );
      if (!mounted) return;
      if (importFailure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not import from that deck (needs at least 3 cards). '
              'You can add cards by hand from here.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    context.go('/teacher/quiz/${deck.id}');
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final cardDecksAsync = ref.watch(teacherCardDecksProvider(null));

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Quiz Deck'),
          leading: BackButton(onPressed: () => context.go(AppRoute.quizDecks)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 40),
                ),
                child: const Text('Create'),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Title is required'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<DictationLanguage>(
                          initialValue: _languageA,
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
                          onChanged: (v) => setState(() => _languageA = v!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<DictationLanguage>(
                          initialValue: _languageB,
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
                          onChanged: (v) => setState(() => _languageB = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  classesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (classes) => classes.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: DropdownButtonFormField<String?>(
                              initialValue: _classId,
                              decoration: const InputDecoration(
                                labelText: 'Assign to class (optional)',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('No class'),
                                ),
                                ...classes.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => _classId = v),
                            ),
                          ),
                  ),

                  const Text(
                    'Where do the cards come from?',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_CreationMethod>(
                    segments: const [
                      ButtonSegment(
                        value: _CreationMethod.blank,
                        label: Text('Start blank'),
                        icon: Icon(Icons.edit_note_outlined),
                      ),
                      ButtonSegment(
                        value: _CreationMethod.fromCardDeck,
                        label: Text('From a card deck'),
                        icon: Icon(Icons.style_outlined),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) =>
                        setState(() => _method = s.first),
                  ),
                  const SizedBox(height: 8),
                  if (_method == _CreationMethod.blank)
                    Text(
                      'You\'ll type each card\'s correct answer plus 2+ wrong '
                      'variants, per language, on the next screen.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    )
                  else
                    cardDecksAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => Text(
                        'Could not load your card decks.',
                        style: TextStyle(color: AppColors.error, fontSize: 12),
                      ),
                      data: (cardDecks) {
                        final eligible = cardDecks
                            .where((d) => d.cards.length >= 3)
                            .toList();
                        if (eligible.isEmpty) {
                          return Text(
                            'None of your card decks have 3+ cards yet — '
                            'add more pairs there first, or start blank.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          );
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: _sourceCardDeckId,
                          decoration: const InputDecoration(
                            labelText: 'Card deck to import from',
                          ),
                          items: eligible
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    '${d.title} (${d.cards.length} cards)',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _sourceCardDeckId = v),
                        );
                      },
                    ),
                  const SizedBox(height: 24),

                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Timer, lives & session length',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Sensible defaults are pre-filled — only change these if you want to.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _sessionLengthCtrl,
                              enabled: !_wholeDeckSession,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Cards per session',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Whole deck'),
                              value: _wholeDeckSession,
                              onChanged: (v) => setState(
                                () => _wholeDeckSession = v ?? false,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _timerInitialCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Starting time per card (seconds)',
                          helperText:
                              'Shortens as the session goes on, down to a 3s floor.',
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
                              onChanged: (v) =>
                                  setState(() => _livesEnabled = v),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _livesCountCtrl,
                              enabled: _livesEnabled,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Lives',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
