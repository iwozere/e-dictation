import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/widgets/ocr_image_button.dart';
import '../../../classes/presentation/providers/classes_provider.dart';
import '../../domain/dictation.dart';
import '../providers/dictations_provider.dart';

class CreateDictationScreen extends ConsumerStatefulWidget {
  const CreateDictationScreen({super.key});

  @override
  ConsumerState<CreateDictationScreen> createState() =>
      _CreateDictationScreenState();
}

class _CreateDictationScreenState extends ConsumerState<CreateDictationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _textFocusNode = FocusNode();

  DictationLanguage _language = DictationLanguage.german;
  DictationDifficulty? _difficulty;
  String? _classId;
  int _pauseSecs = 5;
  bool _allowStudentControls = true;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  int get _wordCount {
    final t = _textCtrl.text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  bool get _overLimit => _wordCount > AppConfig.maxDictationWords;

  void _applyOcrText(String text) {
    final lines = text.split('\n');
    final firstLine = lines.first.trim();
    final rest = lines.skip(1).join('\n').trimLeft();

    // If the title field is empty and the first line is short enough to be a
    // title (≤80 chars, followed by more content), auto-split.
    if (_titleCtrl.text.trim().isEmpty &&
        firstLine.isNotEmpty &&
        firstLine.length <= 80 &&
        rest.isNotEmpty) {
      setState(() {
        _titleCtrl.text = firstLine;
        _textCtrl.text = rest;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title auto-filled from scan')),
      );
    } else {
      setState(() => _textCtrl.text = text);
    }
    _textFocusNode.requestFocus();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_overLimit) return;

    setState(() => _saving = true);
    final (dictation, failure) = await ref
        .read(dictationMutationProvider.notifier)
        .create(
          title: _titleCtrl.text.trim(),
          language: _language,
          fullText: _textCtrl.text.trim(),
          difficulty: _difficulty,
          classId: _classId,
          defaultPauseSecs: _pauseSecs,
          allowStudentControls: _allowStudentControls,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${failure.runtimeType}'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dictation saved! Audio is being generated…'),
        backgroundColor: AppColors.success,
      ),
    );
    context.go(AppRoute.teacherDashboard);
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Dictation'),
          leading: BackButton(onPressed: () => context.go(AppRoute.teacherDashboard)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 40),
                ),
                child: const Text('Save'),
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
                  // Title
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 20),

                  // Language + Difficulty row
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<DictationLanguage>(
                          initialValue: _language,
                          decoration: const InputDecoration(labelText: 'Language'),
                          items: DictationLanguage.values
                              .map((l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l.label),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _language = v!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<DictationDifficulty?>(
                          initialValue: _difficulty,
                          decoration: const InputDecoration(labelText: 'Difficulty'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('—')),
                            ...DictationDifficulty.values.map((d) =>
                                DropdownMenuItem(
                                    value: d, child: Text(d.label))),
                          ],
                          onChanged: (v) => setState(() => _difficulty = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Class assignment
                  classesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (classes) => classes.isEmpty
                        ? const SizedBox.shrink()
                        : DropdownButtonFormField<String?>(
                            initialValue: _classId,
                            decoration:
                                const InputDecoration(labelText: 'Assign to class (optional)'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('No class')),
                              ...classes.map((c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _classId = v),
                          ),
                  ),
                  const SizedBox(height: 20),

                  // Pause duration
                  Row(
                    children: [
                      const Text('Pause between sentences:',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      ...AppConfig.pauseDurations.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${s}s'),
                            selected: _pauseSecs == s,
                            onSelected: (_) => setState(() => _pauseSecs = s),
                            selectedColor: AppColors.primary,
                            labelStyle: TextStyle(
                              color: _pauseSecs == s ? Colors.white : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Student controls toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow student controls',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: const Text(
                        'Students can pause, replay and skip sentences'),
                    value: _allowStudentControls,
                    onChanged: (v) => setState(() => _allowStudentControls = v),
                  ),
                  const SizedBox(height: 8),

                  // Dictation text label + scan button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Dictation text',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      OcrImageButton(
                        onTextExtracted: (text) {
                          _applyOcrText(text);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _textCtrl,
                    focusNode: _textFocusNode,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      hintText: 'Paste or type the dictation text here…',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Text is required' : null,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$_wordCount / ${AppConfig.maxDictationWords}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _overLimit ? AppColors.error : Colors.grey[500],
                      ),
                    ),
                  ),
                  if (_overLimit) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Text exceeds ${AppConfig.maxDictationWords}-word limit.',
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ],
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
