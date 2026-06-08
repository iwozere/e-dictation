import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/pin_hash.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/attempt.dart';
import '../providers/attempts_provider.dart';
import '../widgets/attempt_breakdown.dart';

/// Lets a student review their own past attempts by identifying with the
/// name + PIN they used while practising. Because students play
/// anonymously (no stable auth UID), name + PIN is the only durable key —
/// only students who set a PIN can retrieve their history.
class StudentHistoryScreen extends ConsumerStatefulWidget {
  const StudentHistoryScreen({super.key});

  @override
  ConsumerState<StudentHistoryScreen> createState() =>
      _StudentHistoryScreenState();
}

class _StudentHistoryScreenState extends ConsumerState<StudentHistoryScreen> {
  StudentHistoryQuery? _query;

  @override
  void initState() {
    super.initState();
    _tryPrefillFromPrefs();
  }

  /// If this device already practised with a name + PIN, load history
  /// straight away without re-prompting.
  Future<void> _tryPrefillFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('student_name');
    final pinHash = prefs.getString('student_pin_hash');
    if (!mounted) return;
    if (name != null && name.isNotEmpty && pinHash != null) {
      setState(() => _query = (name: name, pinHash: pinHash));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My results'),
        actions: [
          if (_query != null)
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Use a different name',
              onPressed: () => setState(() => _query = null),
            ),
        ],
      ),
      body: _query == null
          ? _IdentityForm(onSubmit: (q) => setState(() => _query = q))
          : _HistoryList(query: _query!),
    );
  }
}

// ---------------------------------------------------------------------------
// Identity form
// ---------------------------------------------------------------------------

class _IdentityForm extends StatefulWidget {
  const _IdentityForm({required this.onSubmit});
  final void Function(StudentHistoryQuery query) onSubmit;

  @override
  State<_IdentityForm> createState() => _IdentityFormState();
}

class _IdentityFormState extends State<_IdentityForm> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (name.isEmpty || pin.length < 4) {
      setState(() => _error = 'Enter your name and 4-digit PIN.');
      return;
    }
    widget.onSubmit((name: name, pinHash: hashPin(pin)));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Find your results',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the same name and PIN you used while practising. '
                'Only attempts where you set a PIN can be shown.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinCtrl,
                decoration: const InputDecoration(
                  labelText: 'PIN (4 digits)',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Show my results',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History list
// ---------------------------------------------------------------------------

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.query});
  final StudentHistoryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(studentAttemptsProvider(query));

    return attemptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: 'Could not load your results.',
        onRetry: () => ref.invalidate(studentAttemptsProvider(query)),
      ),
      data: (attempts) {
        if (attempts.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'No results found',
            subtitle: 'We could not find attempts for that name and PIN. '
                'Check the spelling and PIN, then try again.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(studentAttemptsProvider(query)),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: attempts.length,
            itemBuilder: (_, i) => _HistoryTile(attempt: attempts[i]),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.attempt});
  final Attempt attempt;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(attempt.scoreCorrect, attempt.scoreTotal);
    final date =
        DateFormat('d MMM yyyy · HH:mm').format(attempt.completedAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(
            '${attempt.scoreCorrect}/${attempt.scoreTotal}',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        title: Text(
          attempt.dictationTitle ?? 'Dictation',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(date,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        children: [
          const Divider(height: 1),
          if (attempt.sentences.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sentence details are not available.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            AttemptBreakdown(attempt: attempt, sentences: attempt.sentences),
        ],
      ),
    );
  }
}

Color _scoreColor(int correct, int total) {
  if (total == 0) return Colors.grey;
  final ratio = correct / total;
  if (ratio == 1.0) return AppColors.success;
  if (ratio >= 0.6) return AppColors.warning;
  return AppColors.error;
}
