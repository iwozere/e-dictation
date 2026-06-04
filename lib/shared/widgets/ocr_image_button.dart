import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../providers/supabase_provider.dart';

/// Scan-image button for the dictation text field.
///
/// Shows a "Scan from image" text button. On tap, opens the image picker,
/// sends the selected image to the `ocr_image` Edge Function, and calls
/// [onTextExtracted] with the result. A loading indicator replaces the
/// button while the request is in flight.
class OcrImageButton extends ConsumerStatefulWidget {
  const OcrImageButton({super.key, required this.onTextExtracted});

  /// Called with the OCR-extracted text when the request succeeds.
  final void Function(String text) onTextExtracted;

  @override
  ConsumerState<OcrImageButton> createState() => _OcrImageButtonState();
}

class _OcrImageButtonState extends ConsumerState<OcrImageButton> {
  bool _loading = false;

  Future<void> _pickAndExtract() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      // Resize on mobile to keep payload manageable; web returns original.
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();

    // Guard against very large images (> 6 MB raw ≈ 8 MB base64).
    if (bytes.length > 6 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image is too large. Please use one under 6 MB.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final base64Image = base64Encode(bytes);
      final mimeType = file.mimeType ?? 'image/jpeg';

      final response = await ref
          .read(supabaseClientProvider)
          .functions
          .invoke(
            'ocr_image',
            body: {'image_base64': base64Image, 'mime_type': mimeType},
          );

      if (!mounted) return;

      final text = response.data['text'] as String? ?? '';
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text found in image.')),
        );
        return;
      }
      widget.onTextExtracted(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return TextButton.icon(
      onPressed: _pickAndExtract,
      icon: const Icon(Icons.document_scanner_outlined, size: 16),
      label: const Text('Scan from image'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
}
