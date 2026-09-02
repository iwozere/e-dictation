import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../classes/presentation/providers/classes_provider.dart';
import '../../../dictations/domain/dictation.dart' show DictationLanguage;
import '../providers/cards_provider.dart';

class CreateCardDeckScreen extends ConsumerStatefulWidget {
  const CreateCardDeckScreen({super.key});

  @override
  ConsumerState<CreateCardDeckScreen> createState() =>
      _CreateCardDeckScreenState();
}

class _CreateCardDeckScreenState extends ConsumerState<CreateCardDeckScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();

  DictationLanguage _languageA = DictationLanguage.german;
  DictationLanguage _languageB = DictationLanguage.english;
  String? _classId;

  XFile? _photo;
  Uint8List? _photoBytes;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (bytes.length > 6 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image is too large. Please use one under 6 MB.'),
        ),
      );
      return;
    }
    setState(() {
      _photo = file;
      _photoBytes = bytes;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_languageA == _languageB) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick two different languages.')),
      );
      return;
    }
    if (_photo == null || _photoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a photo of the word pairs first.')),
      );
      return;
    }

    setState(() => _saving = true);

    final (deck, createFailure) = await ref
        .read(cardDeckMutationProvider.notifier)
        .create(
          title: _titleCtrl.text.trim(),
          languageA: _languageA,
          languageB: _languageB,
          classId: _classId,
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

    final base64Image = base64Encode(_photoBytes!);
    final mimeType = _photo!.mimeType ?? 'image/jpeg';
    final parseFailure = await ref
        .read(cardsRepositoryProvider)
        .parseDeck(
          deckId: deck.id,
          imageBase64: base64Image,
          mimeType: mimeType,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (parseFailure != null) {
      // The deck already exists (status='failed'); let the detail screen
      // show the error and offer a retry rather than losing the deck here.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not read the photo. You can try again from the deck page.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }

    context.go('/teacher/cards/${deck.id}');
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Card Deck'),
          leading: BackButton(onPressed: () => context.go(AppRoute.cardDecks)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 40),
                ),
                child: const Text('Scan'),
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
                  const SizedBox(height: 6),
                  Text(
                    'Students pick either language as their own when they open the link, '
                    'so the order here doesn\'t matter.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),

                  classesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (classes) => classes.isEmpty
                        ? const SizedBox.shrink()
                        : DropdownButtonFormField<String?>(
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
                  const SizedBox(height: 20),

                  const Text(
                    'Photo of the word pairs',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  _PhotoPicker(bytes: _photoBytes, onPick: _pickPhoto),
                  const SizedBox(height: 8),
                  Text(
                    'A clear photo of a two-column list works best. You\'ll be able to review '
                    'and fix every pair before anything is shared with students.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.bytes, required this.onPick});
  final Uint8List? bytes;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 40,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a photo',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes!, fit: BoxFit.cover),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FilledButton.tonalIcon(
                      onPressed: onPick,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Change'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
