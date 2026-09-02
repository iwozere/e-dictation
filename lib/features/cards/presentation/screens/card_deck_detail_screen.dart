import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/card_deck.dart';
import '../../domain/card_pair.dart';
import '../providers/cards_provider.dart';

/// Adapts to the deck's status:
///  - pending  → "processing" spinner (parsing or generating audio), polls
///  - draft    → editable card list + "Save & generate audio"
///  - ready    → share link + read-only card list + "Edit pairs" toggle
///  - failed   → error message + "Try another photo"
class CardDeckDetailScreen extends ConsumerStatefulWidget {
  const CardDeckDetailScreen({super.key, required this.deckId});
  final String deckId;

  @override
  ConsumerState<CardDeckDetailScreen> createState() =>
      _CardDeckDetailScreenState();
}

class _CardDeckDetailScreenState extends ConsumerState<CardDeckDetailScreen> {
  Timer? _pollTimer;
  List<String> _loadedCardIds = const [];
  final Map<String, TextEditingController> _aCtrls = {};
  final Map<String, TextEditingController> _bCtrls = {};
  bool _editing = false;
  bool _busy = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final c in _aCtrls.values) {
      c.dispose();
    }
    for (final c in _bCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers(List<CardPair> cards) {
    final ids = cards.map((c) => c.id).toList();
    if (listEquals(ids, _loadedCardIds)) return;
    _loadedCardIds = ids;
    for (final c in _aCtrls.values) {
      c.dispose();
    }
    for (final c in _bCtrls.values) {
      c.dispose();
    }
    _aCtrls.clear();
    _bCtrls.clear();
    for (final card in cards) {
      _aCtrls[card.id] = TextEditingController(text: card.textA);
      _bCtrls[card.id] = TextEditingController(text: card.textB);
    }
  }

  void _updatePolling(CardDeckStatus status) {
    final shouldPoll = status == CardDeckStatus.pending;
    if (shouldPoll && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        ref.invalidate(cardDeckByIdProvider(widget.deckId));
      });
    } else if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _addPair(CardDeck deck) async {
    final failure = await ref
        .read(cardsRepositoryProvider)
        .addCardPair(deckId: deck.id, position: deck.cards.length);
    if (!mounted) return;
    if (failure.$2 != null) {
      _showError('Could not add a new pair.');
      return;
    }
    ref.invalidate(cardDeckByIdProvider(widget.deckId));
  }

  Future<void> _deletePair(CardPair pair) async {
    final failure = await ref
        .read(cardsRepositoryProvider)
        .deleteCardPair(pair.id);
    if (!mounted) return;
    if (failure != null) {
      _showError('Could not delete that pair.');
      return;
    }
    ref.invalidate(cardDeckByIdProvider(widget.deckId));
  }

  Future<void> _saveAndGenerate(CardDeck deck) async {
    if (deck.cards.isEmpty) {
      _showError('Add at least one pair first.');
      return;
    }
    setState(() => _busy = true);

    // Persist any edited text before generating audio.
    for (final card in deck.cards) {
      final a = _aCtrls[card.id]?.text.trim() ?? card.textA;
      final b = _bCtrls[card.id]?.text.trim() ?? card.textB;
      if (a != card.textA || b != card.textB) {
        await ref
            .read(cardsRepositoryProvider)
            .updateCardPair(id: card.id, textA: a, textB: b);
      }
    }

    final failure = await ref
        .read(cardsRepositoryProvider)
        .generateAudio(deck.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = false;
    });
    if (failure != null) {
      _showError('Could not generate audio. Try again.');
    }
    ref.invalidate(cardDeckByIdProvider(widget.deckId));
  }

  Future<void> _retryWithNewPhoto(CardDeck deck) async {
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
      _showError('Image is too large. Please use one under 6 MB.');
      return;
    }

    setState(() => _busy = true);
    final failure = await ref
        .read(cardsRepositoryProvider)
        .parseDeck(
          deckId: deck.id,
          imageBase64: base64Encode(bytes),
          mimeType: file.mimeType ?? 'image/jpeg',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      _showError('Could not read that photo either. Try a clearer one.');
    }
    ref.invalidate(cardDeckByIdProvider(widget.deckId));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _copyLink(String shareCode) {
    Clipboard.setData(
      ClipboardData(text: '${AppConfig.appBaseUrl}/c/$shareCode'),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied!')));
  }

  @override
  Widget build(BuildContext context) {
    final deckAsync = ref.watch(cardDeckByIdProvider(widget.deckId));

    ref.listen(cardDeckByIdProvider(widget.deckId), (_, next) {
      next.whenData((d) => _updatePolling(d.status));
    });

    return deckAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Card deck')),
        body: ErrorView(
          message: 'Could not load this deck.',
          onRetry: () => ref.invalidate(cardDeckByIdProvider(widget.deckId)),
        ),
      ),
      data: (deck) {
        _syncControllers(deck.cards);

        return Scaffold(
          appBar: AppBar(
            title: SelectionArea(child: Text(deck.title)),
            actions: [
              if (deck.status == CardDeckStatus.ready &&
                  deck.shareCode != null) ...[
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: 'Preview',
                  onPressed: () => context.go('/c/${deck.shareCode}'),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Copy share link',
                  onPressed: () => _copyLink(deck.shareCode!),
                ),
              ],
            ],
          ),
          body: switch (deck.status) {
            CardDeckStatus.pending => _ProcessingView(),
            CardDeckStatus.failed => _FailedView(
              deck: deck,
              busy: _busy,
              onRetry: () => _retryWithNewPhoto(deck),
            ),
            CardDeckStatus.draft => _ReviewView(
              deck: deck,
              aCtrls: _aCtrls,
              bCtrls: _bCtrls,
              busy: _busy,
              onAdd: () => _addPair(deck),
              onDelete: _deletePair,
              onConfirm: () => _saveAndGenerate(deck),
            ),
            CardDeckStatus.ready =>
              _editing
                  ? _ReviewView(
                      deck: deck,
                      aCtrls: _aCtrls,
                      bCtrls: _bCtrls,
                      busy: _busy,
                      onAdd: () => _addPair(deck),
                      onDelete: _deletePair,
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
          Text('Reading your photo…'),
        ],
      ),
    ),
  );
}

class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.deck,
    required this.busy,
    required this.onRetry,
  });
  final CardDeck deck;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (busy) return const Center(child: CircularProgressIndicator());
    return ErrorView(
      message: deck.statusError ?? 'Something went wrong reading that photo.',
      onRetry: onRetry,
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.deck,
    required this.onCopyLink,
    required this.onEdit,
  });
  final CardDeck deck;
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
                '${deck.languageA.label} / ${deck.languageB.label} · ${deck.cards.length} pairs',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit pairs'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...deck.cards.map(
            (c) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                c.hasAudio ? Icons.check_circle : Icons.hourglass_empty,
                color: c.hasAudio ? AppColors.success : Colors.grey,
                size: 18,
              ),
              title: Text(
                '${c.textA}  →  ${c.textB}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.deck,
    required this.aCtrls,
    required this.bCtrls,
    required this.busy,
    required this.onAdd,
    required this.onDelete,
    required this.onConfirm,
  });

  final CardDeck deck;
  final Map<String, TextEditingController> aCtrls;
  final Map<String, TextEditingController> bCtrls;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(CardPair pair) onDelete;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Review the ${deck.cards.length} pairs below before generating audio. '
                  'Fix any misread text — this becomes the answer key students are graded against.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: deck.cards.length,
            itemBuilder: (_, i) {
              final card = deck.cards[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: aCtrls[card.id],
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: deck.languageA.label,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: bCtrls[card.id],
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: deck.languageB.label,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.error,
                      ),
                      tooltip: 'Delete pair',
                      onPressed: () => onDelete(card),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add pair'),
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
