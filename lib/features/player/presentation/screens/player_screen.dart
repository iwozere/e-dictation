import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dictations/domain/dictation.dart';
import '../../../dictations/presentation/providers/dictations_provider.dart';
import '../../domain/playback_state_model.dart';
import '../providers/playback_notifier.dart';
import '../widgets/playback_controls.dart';
import '../widgets/sentence_list.dart';

/// Accepts either a [shareCode] (anonymous student) or a [dictationId]
/// (authenticated user / teacher preview).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, this.shareCode, this.dictationId})
      : assert(shareCode != null || dictationId != null,
            'One of shareCode or dictationId must be provided');

  final String? shareCode;
  final String? dictationId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _signingIn = false;
  String? _loadedDictationId;
  int _loadedSentencesWithAudio = 0;

  // Student typing
  final _answerCtrl = TextEditingController();
  final Map<int, String> _answers = {};
  bool _showResults = false;

  bool get _isStudentView => widget.shareCode != null;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  void _saveAnswer(int index) {
    final text = _answerCtrl.text.trim();
    if (text.isNotEmpty) _answers[index] = text;
  }

  void _submitAnswer(PlaybackStateModel playback) {
    _saveAnswer(playback.currentIndex);
    _answerCtrl.clear();
    final isLast = playback.currentIndex >= playback.sentences.length - 1;
    if (isLast) {
      setState(() => _showResults = true);
    } else {
      ref.read(playbackNotifierProvider.notifier).next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(authStateProvider);

    // Must be called unconditionally before any early returns.
    ref.listen<PlaybackStateModel>(playbackNotifierProvider, (prev, next) {
      if (prev == null) return;
      // Index changed (audio auto-advanced) → save current answer, clear field.
      if (prev.currentIndex != next.currentIndex) {
        _saveAnswer(prev.currentIndex);
        _answerCtrl.clear();
        setState(() {});
      }
      // Playback finished naturally → show results.
      if (_isStudentView &&
          !_showResults &&
          prev.status != PlaybackStatus.completed &&
          next.status == PlaybackStatus.completed) {
        _saveAnswer(next.currentIndex);
        setState(() => _showResults = true);
      }
    });

    if (widget.shareCode != null && userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.shareCode != null && userAsync.valueOrNull == null) {
      _ensureAnonymousSession();
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dictationAsync = widget.shareCode != null
        ? ref.watch(dictationByShareCodeProvider(widget.shareCode!))
        : ref.watch(dictationByIdProvider(widget.dictationId!));

    return dictationAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Dictation')),
        body: ErrorView(message: _errorMessage(e)),
      ),
      data: (dictation) {
        final sentencesWithAudio =
            dictation.sentences.where((s) => s.hasAudio).length;
        if (_loadedDictationId != dictation.id ||
            _loadedSentencesWithAudio != sentencesWithAudio) {
          _loadedDictationId = dictation.id;
          _loadedSentencesWithAudio = sentencesWithAudio;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(playbackNotifierProvider.notifier).loadDictation(
                  dictation.sentences,
                  defaultPauseSecs: dictation.defaultPauseSecs,
                );
          });
        }

        final playback = ref.watch(playbackNotifierProvider);
        final showControls =
            !_isStudentView || dictation.allowStudentControls;

        return Scaffold(
          appBar: AppBar(
            title: Text(dictation.title),
            actions: [
              PopupMenuButton<DictationMode>(
                icon: const Icon(Icons.visibility_outlined),
                tooltip: 'Text visibility',
                initialValue: playback.dictationMode,
                onSelected: (mode) => ref
                    .read(playbackNotifierProvider.notifier)
                    .setDictationMode(mode),
                itemBuilder: (_) => DictationMode.values
                    .map((m) => PopupMenuItem(value: m, child: Text(m.label)))
                    .toList(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: _isStudentView && _showResults
                    ? _ResultsPanel(
                        sentences: dictation.sentences,
                        answers: _answers,
                      )
                    : SentenceListWidget(
                        sentences: dictation.sentences,
                        playbackState: playback,
                      ),
              ),

              // Typing panel — student view only, hidden once results shown.
              if (_isStudentView &&
                  !_showResults &&
                  dictation.sentences.isNotEmpty)
                _TypingPanel(
                  controller: _answerCtrl,
                  currentIndex: playback.currentIndex,
                  totalCount: playback.sentences.length,
                  onSubmit: () => _submitAnswer(playback),
                ),

              const Divider(height: 1),

              if (showControls)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SpeedRow(speed: playback.speed),
                          _PauseRow(pauseSecs: playback.pauseDurationSecs),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PlaybackControls(playbackState: playback),
                      const SizedBox(height: 8),
                      Text(
                        _statusLabel(playback),
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _statusLabel(playback),
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _ensureAnonymousSession() async {
    if (_signingIn) return;
    _signingIn = true;
    final repo = ref.read(authRepositoryProvider);
    await repo.signInAnonymously();
    _signingIn = false;
  }

  String _errorMessage(Object e) {
    if (e is Exception) return 'Dictation not found. Check your share code.';
    return 'Could not load dictation.';
  }

  String _statusLabel(PlaybackStateModel state) => switch (state.status) {
        PlaybackStatus.idle => 'Press play to start',
        PlaybackStatus.loading => 'Loading…',
        PlaybackStatus.playing =>
          'Sentence ${state.currentIndex + 1} of ${state.sentences.length}',
        PlaybackStatus.paused => 'Paused',
        PlaybackStatus.pauseBetweenSentences =>
          'Next sentence in ${state.pauseDurationSecs}s…',
        PlaybackStatus.completed => 'Completed',
        PlaybackStatus.error => state.errorMessage ?? 'Error',
      };
}

// ---------------------------------------------------------------------------
// Typing panel
// ---------------------------------------------------------------------------

class _TypingPanel extends StatelessWidget {
  const _TypingPanel({
    required this.controller,
    required this.currentIndex,
    required this.totalCount,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final int currentIndex;
  final int totalCount;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final isLast = currentIndex >= totalCount - 1;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText:
                      'Type sentence ${currentIndex + 1} of $totalCount…',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                textInputAction:
                    isLast ? TextInputAction.done : TextInputAction.next,
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                // Override the global theme's Size(double.infinity, 48) so
                // the button doesn't consume all row width, leaving 0px for
                // the TextField.
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isLast ? 'Finish' : 'Next →'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results panel
// ---------------------------------------------------------------------------

class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({
    required this.sentences,
    required this.answers,
  });

  final List<DictationSentence> sentences;
  final Map<int, String> answers;

  int get _score => sentences.asMap().entries.where((e) {
        final answer = answers[e.key];
        if (answer == null || answer.isEmpty) return false;
        return _normalize(answer) == _normalize(e.value.text);
      }).length;

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final total = sentences.length;
    final scoreColor = score == total
        ? AppColors.success
        : score >= (total * 0.6).ceil()
            ? AppColors.warning
            : AppColors.error;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Score header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scoreColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                score == total ? Icons.check_circle : Icons.bar_chart_rounded,
                color: scoreColor,
              ),
              const SizedBox(width: 10),
              Text(
                'Score: $score / $total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ...sentences.asMap().entries.map((e) {
          final idx = e.key;
          final sentence = e.value;
          final answer = answers[idx] ?? '';
          final isCorrect = answer.isNotEmpty &&
              _normalize(answer) == _normalize(sentence.text);
          final isBlank = answer.isEmpty;

          final borderColor = isCorrect
              ? AppColors.success
              : isBlank
                  ? Colors.grey
                  : AppColors.error;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCorrect
                          ? Icons.check_circle
                          : isBlank
                              ? Icons.remove_circle_outline
                              : Icons.cancel,
                      size: 16,
                      color: borderColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sentence ${idx + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: borderColor,
                      ),
                    ),
                  ],
                ),
                if (!isCorrect) ...[
                  const SizedBox(height: 8),
                  if (isBlank)
                    Text(
                      sentence.text,
                      style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.success,
                          fontStyle: FontStyle.italic),
                    )
                  else
                    _DiffDisplay(
                      studentText: answer,
                      expectedText: sentence.text,
                    ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Word-level diff
// ---------------------------------------------------------------------------

enum _WordStatus { correct, wrong, missing }

class _DiffWord {
  const _DiffWord(this.word, this.status);
  final String word;
  final _WordStatus status;
}

class _DiffDisplay extends StatelessWidget {
  const _DiffDisplay(
      {required this.studentText, required this.expectedText});
  final String studentText;
  final String expectedText;

  @override
  Widget build(BuildContext context) {
    final diff = _wordDiff(studentText, expectedText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your answer:',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 3),
        Wrap(
          spacing: 3,
          runSpacing: 2,
          children: diff.map((d) {
            return switch (d.status) {
              _WordStatus.correct => Text(d.word,
                  style: const TextStyle(fontSize: 14)),
              _WordStatus.wrong => Text(d.word,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.error,
                      decoration: TextDecoration.lineThrough)),
              _WordStatus.missing => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Text(d.word,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.warning)),
                ),
            };
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text('Correct:',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 3),
        Text(expectedText,
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.success,
                fontStyle: FontStyle.italic)),
      ],
    );
  }

  List<_DiffWord> _wordDiff(String student, String expected) {
    final sw = student.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final ew = expected.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final m = sw.length;
    final n = ew.length;

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        dp[i][j] = _normalize(sw[i - 1]) == _normalize(ew[j - 1])
            ? dp[i - 1][j - 1] + 1
            : max(dp[i - 1][j], dp[i][j - 1]);
      }
    }

    final result = <_DiffWord>[];
    int i = m, j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && _normalize(sw[i - 1]) == _normalize(ew[j - 1])) {
        result.insert(0, _DiffWord(sw[i - 1], _WordStatus.correct));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        result.insert(0, _DiffWord(ew[j - 1], _WordStatus.missing));
        j--;
      } else {
        result.insert(0, _DiffWord(sw[i - 1], _WordStatus.wrong));
        i--;
      }
    }
    return result;
  }
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

// ---------------------------------------------------------------------------
// Speed / Pause rows (unchanged)
// ---------------------------------------------------------------------------

class _SpeedRow extends ConsumerWidget {
  const _SpeedRow({required this.speed});
  final double speed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Speed:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 6),
        ...AppConfig.playbackSpeeds.map(
          (s) => GestureDetector(
            onTap: () => ref.read(playbackNotifierProvider.notifier).setSpeed(s),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: speed == s
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$s×',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: speed == s ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PauseRow extends ConsumerWidget {
  const _PauseRow({required this.pauseSecs});
  final int pauseSecs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pause:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 6),
        ...AppConfig.pauseDurations.map(
          (s) => GestureDetector(
            onTap: () => ref
                .read(playbackNotifierProvider.notifier)
                .setPauseDuration(s),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pauseSecs == s
                    ? AppColors.secondary
                    : AppColors.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${s}s',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: pauseSecs == s ? Colors.white : AppColors.secondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
