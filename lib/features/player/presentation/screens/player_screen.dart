import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/pin_hash.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../attempts/presentation/providers/attempts_provider.dart';
import '../../../attempts/presentation/widgets/student_results_view.dart';
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
  bool _savingAttempt = false;

  // Identity (student view only)
  bool _identityConfirmed = false;
  String? _studentName;
  String? _studentPinHash;
  DateTime? _startedAt;

  // Kept current so _saveAttempt can access it without threading dictation
  // through every call site.
  Dictation? _currentDictation;

  bool get _isStudentView => widget.shareCode != null;

  @override
  void initState() {
    super.initState();
    if (_isStudentView) {
      _loadIdentityFromPrefs();
    } else {
      _identityConfirmed = true;
    }
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIdentityFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _studentName = prefs.getString('student_name');
      _studentPinHash = prefs.getString('student_pin_hash');
    });
  }

  Future<void> _confirmIdentity(String? name, String? pinHash) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null && name.isNotEmpty) {
      await prefs.setString('student_name', name);
    } else {
      await prefs.remove('student_name');
    }
    if (pinHash != null) {
      await prefs.setString('student_pin_hash', pinHash);
    } else {
      await prefs.remove('student_pin_hash');
    }
    if (!mounted) return;
    setState(() {
      _studentName = name?.isEmpty == true ? null : name;
      _studentPinHash = pinHash;
      _identityConfirmed = true;
      _startedAt = DateTime.now();
    });
  }

  /// Persists the textbox content for [index]. An emptied field removes any
  /// previously stored answer so edits (including clearing) round-trip.
  void _saveAnswer(int index) {
    final text = _answerCtrl.text.trim();
    if (text.isNotEmpty) {
      _answers[index] = text;
    } else {
      _answers.remove(index);
    }
  }

  /// Loads the stored answer for [index] into the textbox, cursor at the end.
  void _restoreAnswer(int index) {
    final saved = _answers[index] ?? '';
    _answerCtrl.value = TextEditingValue(
      text: saved,
      selection: TextSelection.collapsed(offset: saved.length),
    );
  }

  void _submitAnswer(PlaybackStateModel playback) {
    _saveAnswer(playback.currentIndex);
    final isLast = playback.currentIndex >= playback.sentences.length - 1;
    if (isLast) {
      // Show results immediately from local answers; persist in background.
      setState(() => _showResults = true);
      unawaited(_saveAttempt());
    } else {
      // The index-change listener saves the current draft and restores the
      // next sentence's answer into the textbox.
      ref.read(playbackNotifierProvider.notifier).next();
    }
  }

  Future<void> _saveAttempt() async {
    if (_savingAttempt || _currentDictation == null) return;
    setState(() => _savingAttempt = true);
    try {
      final (_, failure) = await ref.read(attemptsRepositoryProvider).saveAttempt(
        dictationId: _currentDictation!.id,
        studentName: _studentName,
        studentPinHash: _studentPinHash,
        answers: Map.of(_answers),
        startedAt: _startedAt,
      );
      if (!mounted) return;
      if (failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not save results. Tap Retry to try again.'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Retry', onPressed: _saveAttempt),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAttempt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(authStateProvider);

    // Must be called unconditionally before any early returns.
    ref.listen<PlaybackStateModel>(playbackNotifierProvider, (prev, next) {
      if (prev == null) return;

      // Student typing mode: when a sentence's audio finishes and the
      // between-sentence countdown starts, immediately cancel it and seek
      // back to the sentence start.  The student advances manually with
      // "Next →" / "Finish"; pressing Play replays the current sentence.
      if (_isStudentView &&
          !_showResults &&
          prev.status != PlaybackStatus.pauseBetweenSentences &&
          next.status == PlaybackStatus.pauseBetweenSentences) {
        ref.read(playbackNotifierProvider.notifier).waitForInput();
        return;
      }

      // Index changed (student navigated via the transport buttons, or
      // submitted) → auto-save the current draft and load the target
      // sentence's stored answer so it can be reviewed/edited.
      if (prev.currentIndex != next.currentIndex) {
        _saveAnswer(prev.currentIndex);
        _restoreAnswer(next.currentIndex);
        setState(() {});
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
        _currentDictation = dictation;

        // Show identity panel before loading the player for student view.
        if (_isStudentView && !_identityConfirmed) {
          return _IdentityPanel(
            dictationTitle: dictation.title,
            wordCount: dictation.wordCount,
            initialName: _studentName,
            onConfirm: _confirmIdentity,
          );
        }

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
                    ? StudentResultsView(
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
// Identity panel
// ---------------------------------------------------------------------------

class _IdentityPanel extends StatefulWidget {
  const _IdentityPanel({
    required this.dictationTitle,
    required this.wordCount,
    this.initialName,
    required this.onConfirm,
  });

  final String dictationTitle;
  final int wordCount;
  final String? initialName;
  final Future<void> Function(String? name, String? pinHash) onConfirm;

  @override
  State<_IdentityPanel> createState() => _IdentityPanelState();
}

class _IdentityPanelState extends State<_IdentityPanel> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) _nameCtrl.text = widget.initialName!;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    await widget.onConfirm(
      name.isEmpty ? null : name,
      pin.isEmpty ? null : hashPin(pin),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dictationTitle)),
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
                    Icon(Icons.text_fields,
                        size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.wordCount} words',
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 13),
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
                  onSubmitted: (_) => _starting ? null : _start(),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _starting ? null : _start,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: _starting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Start Dictation',
                          style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.push(AppRoute.studentHistory),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('See my past results'),
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
// Speed / Pause rows
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
